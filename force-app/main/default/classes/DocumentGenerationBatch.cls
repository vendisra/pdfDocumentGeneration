/**
 * @description Batch Apex for bulk document generation.
 * Processes large volumes of records efficiently with proper governor limit handling.
 * 
 * FEATURES:
 * - Processes documents in configurable batch sizes
 * - Schedulable for automated generation
 * - Detailed logging and error tracking
 * - Supports any object with a configured template
 * 
 * USAGE:
 * 
 * // Option 1: Execute immediately with record IDs
 * List<Id> quoteIds = new List<Id>{'0Q0xx...', '0Q0xx...', '0Q0xx...'};
 * Id jobId = Database.executeBatch(new DocumentGenerationBatch(quoteIds, 'SalesQuote'), 10);
 * 
 * // Option 2: Execute with a query
 * String query = 'SELECT Id FROM Quote WHERE Status = \'Approved\' AND CreatedDate = TODAY';
 * Id jobId = Database.executeBatch(new DocumentGenerationBatch(query, 'SalesQuote'), 10);
 * 
 * // Option 3: Schedule for recurring execution
 * String cronExp = '0 0 6 * * ?'; // Daily at 6 AM
 * System.schedule('Daily Quote PDFs', cronExp, new DocumentGenerationBatch.Scheduler('SalesQuote'));
 * 
 * BATCH SIZE RECOMMENDATIONS:
 * - 10-20: Safe for most templates (recommended)
 * - 5-10: Complex templates with large child data
 * - 20-30: Simple templates, fast GAS response
 * 
 * LIMITS:
 * - 100 callouts per batch execution
 * - Each document = ~2 callouts (POST + redirect)
 * - Max ~50 documents per batch, but 10-20 recommended for reliability
 * 
 * @author Document Generation Framework
 * @since 2024
 */
public class DocumentGenerationBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
    
    // Configuration
    private String templateName;
    private String query;
    private List<Id> recordIds;
    
    // Stateful tracking (persists across batch executions)
    private Integer totalRecords = 0;
    private Integer successCount = 0;
    private Integer failureCount = 0;
    private List<String> errors = new List<String>();
    private Long startTime;
    
    // Constants
    private static final Integer DEFAULT_BATCH_SIZE = 10;
    private static final Integer MAX_ERRORS_TO_TRACK = 100;
    
    /**
     * @description Constructor with record IDs
     * @param recordIds List of record IDs to process
     * @param templateName The template developer name
     */
    public DocumentGenerationBatch(List<Id> recordIds, String templateName) {
        this.recordIds = recordIds;
        this.templateName = templateName;
        this.totalRecords = recordIds.size();
    }
    
    /**
     * @description Constructor with SOQL query
     * @param query SOQL query to select records (must include Id)
     * @param templateName The template developer name
     */
    public DocumentGenerationBatch(String query, String templateName) {
        this.query = query;
        this.templateName = templateName;
    }
    
    /**
     * @description Start method - returns the query locator
     */
    public Database.QueryLocator start(Database.BatchableContext context) {
        startTime = System.currentTimeMillis();
        
        System.debug(LoggingLevel.INFO, '═══════════════════════════════════════════════════');
        System.debug(LoggingLevel.INFO, 'DOCUMENT GENERATION BATCH STARTED');
        System.debug(LoggingLevel.INFO, 'Template: ' + templateName);
        System.debug(LoggingLevel.INFO, 'Job ID: ' + context.getJobId());
        System.debug(LoggingLevel.INFO, '═══════════════════════════════════════════════════');
        
        if (String.isNotBlank(query)) {
            return Database.getQueryLocator(query);
        } else if (recordIds != null && !recordIds.isEmpty()) {
            // Determine object type from first ID
            String objectType = recordIds[0].getSObjectType().getDescribe().getName();
            String dynamicQuery = 'SELECT Id FROM ' + String.escapeSingleQuotes(objectType) + 
                                  ' WHERE Id IN :recordIds';
            return Database.getQueryLocator(dynamicQuery);
        } else {
            throw new DocumentGenerationBatchException('Either recordIds or query must be provided');
        }
    }
    
    /**
     * @description Execute method - processes each batch of records
     */
    public void execute(Database.BatchableContext context, List<SObject> scope) {
        System.debug(LoggingLevel.INFO, 'Processing batch of ' + scope.size() + ' records...');
        
        for (SObject record : scope) {
            Id recordId = record.Id;
            
            try {
                // Use existing core logic
                DocumentMergeService.DocumentRequest request = new DocumentMergeService.DocumentRequest();
                request.recordId = recordId;
                request.templateDeveloperName = templateName;
                request.attachToRecord = true;
                
                DocumentMergeService.DocumentResult result = DocumentMergeService.generateDocument(request);
                
                if (result.success) {
                    successCount++;
                    System.debug(LoggingLevel.INFO, '✓ Generated document for: ' + recordId);
                } else {
                    failureCount++;
                    trackError(recordId, result.errorMessage);
                    System.debug(LoggingLevel.ERROR, '✗ Failed for ' + recordId + ': ' + result.errorMessage);
                }
                
            } catch (Exception e) {
                failureCount++;
                trackError(recordId, e.getMessage());
                System.debug(LoggingLevel.ERROR, '✗ Exception for ' + recordId + ': ' + e.getMessage());
            }
        }
    }
    
    /**
     * @description Finish method - logs summary and sends notification
     */
    public void finish(Database.BatchableContext context) {
        Long duration = System.currentTimeMillis() - startTime;
        
        System.debug(LoggingLevel.INFO, '═══════════════════════════════════════════════════');
        System.debug(LoggingLevel.INFO, 'DOCUMENT GENERATION BATCH COMPLETED');
        System.debug(LoggingLevel.INFO, '═══════════════════════════════════════════════════');
        System.debug(LoggingLevel.INFO, 'Total Records: ' + (successCount + failureCount));
        System.debug(LoggingLevel.INFO, 'Successful: ' + successCount);
        System.debug(LoggingLevel.INFO, 'Failed: ' + failureCount);
        System.debug(LoggingLevel.INFO, 'Duration: ' + duration + 'ms');
        System.debug(LoggingLevel.INFO, '═══════════════════════════════════════════════════');
        
        if (!errors.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'ERRORS:');
            for (String error : errors) {
                System.debug(LoggingLevel.ERROR, '  - ' + error);
            }
        }
        
        // Create summary log record
        createSummaryLog(context.getJobId(), duration);
        
        // Optional: Send email notification
        if (failureCount > 0) {
            sendNotificationEmail(context.getJobId(), duration);
        }
    }
    
    /**
     * @description Tracks errors up to the maximum limit
     */
    private void trackError(Id recordId, String message) {
        if (errors.size() < MAX_ERRORS_TO_TRACK) {
            errors.add(recordId + ': ' + (message != null ? message.abbreviate(200) : 'Unknown error'));
        }
    }
    
    /**
     * @description Creates a summary log record
     */
    private void createSummaryLog(Id jobId, Long duration) {
        if (!GoogleAuthService.isLoggingEnabled()) {
            return;
        }
        
        try {
            DocumentGenerationLog__c log = new DocumentGenerationLog__c();
            log.RecordId__c = 'BATCH_JOB';
            log.ObjectApiName__c = 'AsyncApexJob';
            log.TemplateName__c = templateName;
            log.Status__c = failureCount == 0 ? 'Success' : 'Partial Success';
            log.DurationMs__c = duration;
            log.GeneratedBy__c = UserInfo.getUserId();
            log.ErrorMessage__c = 'Batch Summary - Success: ' + successCount + ', Failed: ' + failureCount + 
                                  (errors.isEmpty() ? '' : '\n\nErrors:\n' + String.join(errors, '\n'));
            
            insert log;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to create summary log: ' + e.getMessage());
        }
    }
    
    /**
     * @description Sends email notification on failures
     */
    private void sendNotificationEmail(Id jobId, Long duration) {
        try {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ UserInfo.getUserEmail() });
            email.setSubject('Document Generation Batch Completed with Errors');
            email.setPlainTextBody(
                'Document Generation Batch Job Completed\n\n' +
                'Job ID: ' + jobId + '\n' +
                'Template: ' + templateName + '\n' +
                'Successful: ' + successCount + '\n' +
                'Failed: ' + failureCount + '\n' +
                'Duration: ' + (duration / 1000) + ' seconds\n\n' +
                'Errors:\n' + String.join(errors, '\n')
            );
            
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Failed to send notification email: ' + e.getMessage());
        }
    }
    
    /**
     * @description Custom exception for batch errors
     */
    public class DocumentGenerationBatchException extends Exception {}
    
    // =========================================================================
    // STATIC HELPER METHODS
    // =========================================================================
    
    /**
     * @description Execute batch for a list of record IDs
     * @param recordIds List of record IDs
     * @param templateName Template developer name
     * @return Id The batch job ID
     */
    public static Id executeBatch(List<Id> recordIds, String templateName) {
        return executeBatch(recordIds, templateName, DEFAULT_BATCH_SIZE);
    }
    
    /**
     * @description Execute batch for a list of record IDs with custom batch size
     * @param recordIds List of record IDs
     * @param templateName Template developer name
     * @param batchSize Number of records per batch (recommended: 10-20)
     * @return Id The batch job ID
     */
    public static Id executeBatch(List<Id> recordIds, String templateName, Integer batchSize) {
        if (recordIds == null || recordIds.isEmpty()) {
            throw new DocumentGenerationBatchException('Record IDs cannot be empty');
        }
        
        DocumentGenerationBatch batch = new DocumentGenerationBatch(recordIds, templateName);
        return Database.executeBatch(batch, batchSize);
    }
    
    /**
     * @description Execute batch with a SOQL query
     * @param query SOQL query (must include Id field)
     * @param templateName Template developer name
     * @return Id The batch job ID
     */
    public static Id executeBatchWithQuery(String query, String templateName) {
        return executeBatchWithQuery(query, templateName, DEFAULT_BATCH_SIZE);
    }
    
    /**
     * @description Execute batch with a SOQL query and custom batch size
     * @param query SOQL query (must include Id field)
     * @param templateName Template developer name
     * @param batchSize Number of records per batch
     * @return Id The batch job ID
     */
    public static Id executeBatchWithQuery(String query, String templateName, Integer batchSize) {
        if (String.isBlank(query)) {
            throw new DocumentGenerationBatchException('Query cannot be empty');
        }
        
        DocumentGenerationBatch batch = new DocumentGenerationBatch(query, templateName);
        return Database.executeBatch(batch, batchSize);
    }
    
    // =========================================================================
    // SCHEDULABLE INNER CLASS
    // =========================================================================
    
    /**
     * @description Schedulable class for recurring document generation
     * 
     * USAGE:
     * // Schedule daily at 6 AM
     * String cronExp = '0 0 6 * * ?';
     * System.schedule('Daily Invoice PDFs', cronExp, 
     *     new DocumentGenerationBatch.Scheduler(
     *         'SELECT Id FROM Invoice__c WHERE Status__c = \'Approved\' AND PDF_Generated__c = false',
     *         'InvoiceTemplate'
     *     )
     * );
     */
    public class Scheduler implements Schedulable {
        private String query;
        private String templateName;
        private Integer batchSize;
        
        /**
         * @description Constructor with query
         * @param query SOQL query to select records
         * @param templateName Template developer name
         */
        public Scheduler(String query, String templateName) {
            this(query, templateName, DEFAULT_BATCH_SIZE);
        }
        
        /**
         * @description Constructor with query and batch size
         * @param query SOQL query to select records
         * @param templateName Template developer name
         * @param batchSize Records per batch
         */
        public Scheduler(String query, String templateName, Integer batchSize) {
            this.query = query;
            this.templateName = templateName;
            this.batchSize = batchSize;
        }
        
        /**
         * @description Execute method called by scheduler
         */
        public void execute(SchedulableContext context) {
            System.debug(LoggingLevel.INFO, 'Scheduled document generation starting...');
            DocumentGenerationBatch.executeBatchWithQuery(query, templateName, batchSize);
        }
    }
}
