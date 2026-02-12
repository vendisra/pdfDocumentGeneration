/**
 * Test document generation for any template + record.
 * Edit RECORD_ID and TEMPLATE_NAME below, then execute in Developer Console.
 * 
 * All document generation is ASYNCHRONOUS via Queueable jobs.
 * After running, check:
 * - Setup > Apex Jobs for job status
 * - DocumentGenerationLog__c for detailed results
 * - Files (ContentDocument) linked to your record
 */

// CONFIGURATION - Update these values
String RECORD_ID = '006DS00000NY3S9YAL';   // Your record ID
String TEMPLATE_NAME = 'ProfessionalInvoice';  // Your template name

// EXECUTE
DocumentGeneratorAction.DocumentGeneratorOutput result = 
    DocumentGeneratorAction.generateDocument(RECORD_ID, TEMPLATE_NAME);

System.debug('=== DOCUMENT GENERATION QUEUED ===');
System.debug('Job ID: ' + result.asyncJobId);
System.debug('');
System.debug('Next steps:');
System.debug('1. Go to Setup > Apex Jobs to monitor progress');
System.debug('2. Query: SELECT Id, Status__c, ContentDocumentId__c, ErrorMessage__c FROM DocumentGenerationLog__c ORDER BY CreatedDate DESC LIMIT 1');
System.debug('3. Check Files related list on your record');
