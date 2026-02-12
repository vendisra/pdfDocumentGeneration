/**
 * @description Queueable class for asynchronous document generation.
 * 
 * DESIGN:
 * - Processes multiple documents per Queueable job (batched)
 * - Each job processes up to BATCH_SIZE documents (default: 10)
 * - Chains to next batch only when more remain
 * - Efficient: 100 documents = 10 jobs instead of 100 jobs
 * 
 * LIMITS CONSIDERED:
 * - Callout limit: 100 per transaction (we use 10 to leave headroom)
 * - Queueable chain depth: 5 in Developer Edition (unlimited in Enterprise but subject to daily limits)
 * - Daily async limit: Varies by org (this approach minimizes consumption)
 * 
 * USAGE:
 * // Single document
 * DocumentGenerationQueueable.enqueue(recordId, 'SalesQuote');
 * 
 * // Multiple documents (batches automatically)
 * DocumentGenerationQueueable.enqueueMultiple(recordIds, 'SalesQuote');
 * 
 * @author Document Generation Framework
 * @since 2024
 */
public with sharing class DocumentGenerationQueueable implements Queueable, Database.AllowsCallouts {
    
    private List<Id> recordIds;
    private String templateName;
    private Integer startIndex;
    
    // Number of documents to process per Queueable job
    // Keep low to stay well under 100 callout limit and allow for retries/overhead
    private static final Integer BATCH_SIZE = 10;
    
    // Maximum records before recommending Batch Apex
    private static final Integer BATCH_APEX_THRESHOLD = 200;
    
    /**
     * @description Constructor for single document
     * @param recordId The record ID to generate document for
     * @param templateName The template developer name
     */
    public DocumentGenerationQueueable(Id recordId, String templateName) {
        this.recordIds = new List<Id>{ recordId };
        this.templateName = templateName;
        this.startIndex = 0;
    }
    
    /**
     * @description Constructor for multiple documents
     * @param recordIds List of record IDs
     * @param templateName The template developer name
     */
    public DocumentGenerationQueueable(List<Id> recordIds, String templateName) {
        this.recordIds = recordIds;
        this.templateName = templateName;
        this.startIndex = 0;
        
        if (recordIds.size() > BATCH_APEX_THRESHOLD) {
            System.debug(LoggingLevel.WARN, 
                'Consider using DocumentGenerationBatch for ' + recordIds.size() + ' documents.');
        }
    }
    
    /**
     * @description Private constructor for chaining with batch offset
     */
    private DocumentGenerationQueueable(List<Id> recordIds, String templateName, Integer startIndex) {
        this.recordIds = recordIds;
        this.templateName = templateName;
        this.startIndex = startIndex;
    }
    
    /**
     * @description Execute - processes a batch of documents, then chains for remaining
     */
    public void execute(QueueableContext context) {
        if (recordIds == null || startIndex >= recordIds.size()) {
            System.debug(LoggingLevel.INFO, 'Document generation queue complete.');
            return;
        }
        
        Integer endIndex = Math.min(startIndex + BATCH_SIZE, recordIds.size());
        Integer batchNumber = (startIndex / BATCH_SIZE) + 1;
        Integer totalBatches = (Integer) Math.ceil((Decimal) recordIds.size() / BATCH_SIZE);
        
        System.debug(LoggingLevel.INFO, 'Processing batch ' + batchNumber + ' of ' + totalBatches + 
                    ' (records ' + (startIndex + 1) + '-' + endIndex + ' of ' + recordIds.size() + ')');
        
        Integer successCount = 0;
        Integer failCount = 0;
        List<DocumentGenerationLog__c> errorLogs = new List<DocumentGenerationLog__c>();
        
        // Process batch of documents
        for (Integer i = startIndex; i < endIndex; i++) {
            Id recordId = recordIds[i];
            
            try {
                DocumentMergeService.DocumentRequest request = new DocumentMergeService.DocumentRequest();
                request.recordId = recordId;
                request.templateDeveloperName = templateName;
                request.attachToRecord = true;
                
                DocumentMergeService.DocumentResult result = DocumentMergeService.generateDocument(request);
                
                if (result.success) {
                    successCount++;
                    System.debug(LoggingLevel.DEBUG, 'Success: ' + recordId);
                } else {
                    failCount++;
                    System.debug(LoggingLevel.ERROR, 'Failed: ' + recordId + ' - ' + result.errorMessage);
                    errorLogs.add(createErrorLog(recordId, result.errorMessage));
                }
                
            } catch (Exception e) {
                failCount++;
                System.debug(LoggingLevel.ERROR, 'Exception for ' + recordId + ': ' + e.getMessage());
                errorLogs.add(createErrorLog(recordId, e.getMessage()));
            }
            
            // Check callout limits - stop if we're getting close
            if (Limits.getCallouts() >= Limits.getLimitCallouts() - 2) {
                System.debug(LoggingLevel.WARN, 'Approaching callout limit, stopping batch early at index ' + i);
                endIndex = i + 1; // Adjust end index for accurate chaining
                break;
            }
        }
        
        // Bulk insert error logs
        if (!errorLogs.isEmpty() && GoogleAuthService.isLoggingEnabled()) {
            try {
                insert errorLogs;
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Failed to insert error logs: ' + e.getMessage());
            }
        }
        
        System.debug(LoggingLevel.INFO, 'Batch ' + batchNumber + ' complete: ' + 
                    successCount + ' success, ' + failCount + ' failed');
        
        // Chain to next batch if more remain
        chainNextBatch(endIndex);
    }
    
    /**
     * @description Chains to next batch of documents
     */
    private void chainNextBatch(Integer nextStartIndex) {
        if (nextStartIndex >= recordIds.size()) {
            System.debug(LoggingLevel.INFO, 'All batches complete. Total records: ' + recordIds.size());
            return;
        }
        
        Integer remainingRecords = recordIds.size() - nextStartIndex;
        Integer remainingBatches = (Integer) Math.ceil((Decimal) remainingRecords / BATCH_SIZE);
        
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.debug(LoggingLevel.INFO, 'Chaining to next batch. Remaining: ' + 
                        remainingRecords + ' records in ' + remainingBatches + ' batch(es)');
            System.enqueueJob(new DocumentGenerationQueueable(recordIds, templateName, nextStartIndex));
        } else {
            System.debug(LoggingLevel.ERROR, 'Cannot chain - queueable limit reached. ' +
                        'Remaining unprocessed: ' + remainingRecords + ' records. ' +
                        'Consider using DocumentGenerationBatch for large volumes.');
        }
    }
    
    /**
     * @description Creates an error log record (not inserted - for bulk insert)
     */
    private DocumentGenerationLog__c createErrorLog(Id recordId, String errorMessage) {
        DocumentGenerationLog__c log = new DocumentGenerationLog__c();
        log.RecordId__c = String.valueOf(recordId);
        log.ObjectApiName__c = recordId != null
            ? recordId.getSObjectType().getDescribe().getName()
            : null;
        log.TemplateName__c = templateName;
        log.Status__c = 'Failed';
        log.ErrorMessage__c = errorMessage?.abbreviate(32000);
        log.GeneratedBy__c = UserInfo.getUserId();
        return log;
    }
    
    // =========================================================================
    // STATIC HELPER METHODS
    // =========================================================================
    
    /**
     * @description Enqueue single document generation
     * @param recordId The record ID
     * @param templateName The template developer name
     * @return Id The Queueable job ID
     */
    public static Id enqueue(Id recordId, String templateName) {
        return System.enqueueJob(new DocumentGenerationQueueable(recordId, templateName));
    }
    
    /**
     * @description Enqueue multiple documents (batches automatically)
     * @param recordIds List of record IDs
     * @param templateName The template developer name
     * @return Id The first Queueable job ID
     */
    public static Id enqueueMultiple(List<Id> recordIds, String templateName) {
        if (recordIds == null || recordIds.isEmpty()) {
            return null;
        }
        
        Integer numBatches = (Integer) Math.ceil((Decimal) recordIds.size() / BATCH_SIZE);
        System.debug(LoggingLevel.INFO, 'Enqueueing ' + recordIds.size() + ' documents in ' + 
                    numBatches + ' batch(es) of up to ' + BATCH_SIZE);
        
        if (recordIds.size() > BATCH_APEX_THRESHOLD) {
            System.debug(LoggingLevel.WARN, 
                'For ' + recordIds.size() + ' documents, consider using DocumentGenerationBatch instead.');
        }
        
        return System.enqueueJob(new DocumentGenerationQueueable(recordIds, templateName));
    }
    
    /**
     * @description Get the current batch size setting
     * @return Integer The number of documents processed per Queueable job
     */
    public static Integer getBatchSize() {
        return BATCH_SIZE;
    }
}
