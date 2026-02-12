/**
 * @description THE PUBLIC API for generating PDF documents from Google Doc templates.
 * Use this class for all document generation - from Flows, Apex, or any automation.
 * 
 * ╔══════════════════════════════════════════════════════════════════════════════╗
 * ║  USAGE FROM APEX:                                                            ║
 * ║                                                                              ║
 * ║  // Generate document (async - returns job ID):                              ║
 * ║  DocumentGeneratorAction.generateDocument(recordId, 'TemplateName');         ║
 * ║                                                                              ║
 * ║  // Multiple records (batched via Queueable):                                ║
 * ║  DocumentGeneratorAction.generateDocumentsAsync(recordIds, 'TemplateName');  ║
 * ║                                                                              ║
 * ║  // Full control via Input class:                                            ║
 * ║  DocumentGeneratorAction.DocumentGeneratorInput input = new ...();           ║
 * ║  input.recordId = recordId;                                                  ║
 * ║  input.templateDeveloperName = 'TemplateName';                               ║
 * ║  DocumentGeneratorAction.generateDocuments(new List<...>{ input });          ║
 * ╚══════════════════════════════════════════════════════════════════════════════╝
 * 
 * PROCESSING:
 * All document generation is ASYNCHRONOUS via Queueable jobs.
 * This ensures:
 * - No "uncommitted work pending" errors in Record-Triggered Flows
 * - Reliable execution regardless of calling context
 * - Consistent behavior across all Flow types and Apex contexts
 * 
 * ARCHITECTURE:
 * 1. Apex enqueues Queueable job
 * 2. Queueable calls GAS middleware
 * 3. GAS generates PDF and uploads directly to Salesforce via JWT
 * 4. Result is logged in DocumentGenerationLog__c
 * 
 * @author Document Generation Framework
 * @since 2024
 */
public with sharing class DocumentGeneratorAction {
    
    /**
     * @description Input class for the invocable action
     */
    public class DocumentGeneratorInput {
        @InvocableVariable(Label='Record ID' Description='The ID of the record to generate document for' Required=true)
        public Id recordId;
        
        @InvocableVariable(Label='Template Developer Name' Description='The developer name of the template to use. If blank, auto-detects based on object type.')
        public String templateDeveloperName;
        
        @InvocableVariable(Label='Output File Name' Description='Custom filename for the generated PDF.')
        public String outputFileName;
        
        @InvocableVariable(Label='Attach to Record' Description='Whether to attach the PDF to the record as a file. Default: true')
        public Boolean attachToRecord;
        
        @InvocableVariable(Label='Additional Merge Fields JSON' Description='JSON string of additional merge field key-value pairs')
        public String additionalMergeFieldsJson;
    }
    
    /**
     * @description Output class for the invocable action
     */
    public class DocumentGeneratorOutput {
        @InvocableVariable(Label='Is Success' Description='Whether the document generation was successful or queued')
        public Boolean isSuccess;
        
        @InvocableVariable(Label='Content Document ID' Description='The ID of the generated ContentDocument (null if async)')
        public Id contentDocumentId;
        
        @InvocableVariable(Label='Content Version ID' Description='The ID of the generated ContentVersion (null if async)')
        public Id contentVersionId;
        
        @InvocableVariable(Label='Error Message' Description='Error message if generation failed')
        public String errorMessage;
        
        @InvocableVariable(Label='Duration (ms)' Description='Time taken to generate the document in milliseconds')
        public Long durationMs;
        
        @InvocableVariable(Label='Generated File Name' Description='The name of the generated PDF file')
        public String generatedFileName;
        
        @InvocableVariable(Label='Download URL' Description='URL to download the generated PDF')
        public String downloadUrl;
        
        @InvocableVariable(Label='Async Job ID' Description='The Queueable job ID if processed asynchronously')
        public Id asyncJobId;
        
        @InvocableVariable(Label='Is Async' Description='True if the request was queued for async processing')
        public Boolean isAsync;
    }
    
    /**
     * @description Main invocable method for document generation
     * All requests are processed asynchronously via Queueable jobs
     * @param inputs List of generation inputs
     * @return List<DocumentGeneratorOutput> List of generation results with job IDs
     */
    @InvocableMethod(
        Label='Generate PDF Document'
        Description='Generates a PDF document from a Google Doc template via GAS middleware. Always processes asynchronously for reliability.'
        Category='Document Generation'
    )
    public static List<DocumentGeneratorOutput> generateDocuments(List<DocumentGeneratorInput> inputs) {
        List<DocumentGeneratorOutput> outputs = new List<DocumentGeneratorOutput>();
        
        // Collect record IDs and determine template
        List<Id> recordIds = new List<Id>();
        String templateName = null;
        
        for (DocumentGeneratorInput input : inputs) {
            recordIds.add(input.recordId);
            // Use first non-blank template name
            if (templateName == null && String.isNotBlank(input.templateDeveloperName)) {
                templateName = input.templateDeveloperName;
            }
        }
        
        // Queue for async processing
        Id jobId = DocumentGenerationQueueable.enqueueMultiple(recordIds, templateName);
        
        // Return async response for all inputs
        for (DocumentGeneratorInput input : inputs) {
            DocumentGeneratorOutput output = new DocumentGeneratorOutput();
            output.isSuccess = true;
            output.isAsync = true;
            output.asyncJobId = jobId;
            outputs.add(output);
        }
        
        return outputs;
    }
    
    /**
     * @description Convenience method for generating a document from Apex
     * @param recordId The record to generate the document for
     * @param templateName The developer name of the template
     * @return DocumentGeneratorOutput with async job ID
     */
    public static DocumentGeneratorOutput generateDocument(Id recordId, String templateName) {
        DocumentGeneratorInput input = new DocumentGeneratorInput();
        input.recordId = recordId;
        input.templateDeveloperName = templateName;
        input.attachToRecord = true;
        
        List<DocumentGeneratorOutput> results = generateDocuments(new List<DocumentGeneratorInput>{ input });
        return results[0];
    }
    
    /**
     * @description Generates documents for multiple records asynchronously
     * @param recordIds List of record IDs to generate documents for
     * @param templateName The developer name of the template
     * @return Id The Queueable job ID
     */
    public static Id generateDocumentsAsync(List<Id> recordIds, String templateName) {
        return DocumentGenerationQueueable.enqueueMultiple(recordIds, templateName);
    }
    
    /**
     * @description Generates a single document asynchronously
     * @param recordId The record to generate the document for
     * @param templateName The developer name of the template
     * @return Id The Queueable job ID
     */
    public static Id generateDocumentAsync(Id recordId, String templateName) {
        return DocumentGenerationQueueable.enqueue(recordId, templateName);
    }
}
