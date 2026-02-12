/**
 * Validates template and populates ParsedFieldsJSON__c.
 * Note: If template doesn't exist, run twice - first creates, second validates.
 */

// CONFIGURATION
String GOOGLE_DOC_ID = '1bS0JfDwlI6LP_WjYqpUQxv4UqxzM6c0AbIAUKvA38b4';
String TEMPLATE_NAME = 'ProfessionalInvoice';
String OBJECT_API_NAME = 'Opportunity';

// Check if template exists
List<DocumentTemplate__c> existing = [SELECT Id, GoogleDocId__c FROM DocumentTemplate__c WHERE Name = :TEMPLATE_NAME LIMIT 1];

if (existing.isEmpty()) {
    // Create template - run script again to validate
    DocumentTemplate__c template = new DocumentTemplate__c(
        Name = TEMPLATE_NAME,
        GoogleDocId__c = GOOGLE_DOC_ID,
        ObjectApiName__c = OBJECT_API_NAME,
        IsActive__c = true
    );
    insert template;
    System.debug('Template created. RUN AGAIN to validate.');
} else if (existing[0].GoogleDocId__c != GOOGLE_DOC_ID) {
    // Update Google Doc ID - run script again to validate
    existing[0].GoogleDocId__c = GOOGLE_DOC_ID;
    update existing[0];
    System.debug('Template updated. RUN AGAIN to validate.');
} else {
    // Validate (no DML, so callout is allowed)
    TemplateValidationService.ValidationResult result = TemplateValidationService.validateAndUpdateTemplate(existing[0].Id);

    System.debug('Status: ' + result.status);
    System.debug('Fields: ' + result.mainObjectFieldCount + ' main, ' + result.parentRelationshipCount + ' parent, ' + result.childRelationshipCount + ' child');
    if (result.dataSourceCount > 0) {
        System.debug('Data Sources: ' + result.dataSourceCount);
    }

    for (String err : result.errors) System.debug('ERROR: ' + err);
    for (String warn : result.warnings) System.debug('WARN: ' + warn);
}
