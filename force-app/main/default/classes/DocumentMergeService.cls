/**
 * @description Internal orchestration service for document generation.
 * Coordinates data fetching from Salesforce and document generation via GAS middleware.
 * 
 * ╔══════════════════════════════════════════════════════════════════════════════╗
 * ║  INTERNAL USE ONLY - Do not call directly from external code                 ║
 * ║                                                                              ║
 * ║  Use DocumentGeneratorAction instead:                                        ║
 * ║  - DocumentGeneratorAction.generateDocument(recordId, templateName)          ║
 * ║  - DocumentGeneratorAction.generateDocumentSync(recordId, templateName)      ║
 * ║  - DocumentGeneratorAction.generateDocuments(inputs) // For Flows            ║
 * ╚══════════════════════════════════════════════════════════════════════════════╝
 * 
 * Architecture:
 * - DataProviderService: Fetches Salesforce data with FLS enforcement
 * - GASDocumentService: Communicates with Google Apps Script Web App
 * - GoogleDriveService: Stores generated PDF in Salesforce Files
 * 
 * IMPORTANT: Log records are created AFTER callouts to avoid 
 * "uncommitted work pending" errors.
 * 
 * @author Document Generation Framework
 * @since 2024
 */
public with sharing class DocumentMergeService {
    
    /**
     * @description Custom exception for document merge errors
     */
    public class DocumentMergeException extends Exception {}
    
    /**
     * @description Request class for document generation
     */
    public class DocumentRequest {
        public Id recordId;
        public String templateDeveloperName;
        public String outputFileName;
        public Boolean attachToRecord = true;
        public Map<String, String> additionalMergeFields;
        
        public DocumentRequest() {
            this.additionalMergeFields = new Map<String, String>();
        }
    }
    
    /**
     * @description Result class for document generation
     */
    public class DocumentResult {
        public Boolean success;
        public Id contentDocumentId;
        public Id contentVersionId;
        public String errorMessage;
        public Long durationMs;
        public String generatedFileName;
        public List<String> warnings;
        
        public DocumentResult() {
            this.success = false;
            this.warnings = new List<String>();
        }
        
        public void addWarning(String message) {
            if (String.isNotBlank(message)) {
                this.warnings.add(message);
            }
        }
        
        public Boolean hasWarnings() {
            return !this.warnings.isEmpty();
        }
    }
    
    /**
     * @description Generates a PDF document for a single record
     * @param request The document generation request
     * @return DocumentResult The result of the generation
     */
    public static DocumentResult generateDocument(DocumentRequest request) {
        Long startTime = System.currentTimeMillis();
        DocumentResult result = new DocumentResult();
        DocumentTemplate__c template = null;
        
        try {
            // Validate request
            validateRequest(request);
            
            // Get template configuration
            template = getTemplate(request.templateDeveloperName, request.recordId);
            
            // Validate template has been validated (fail fast)
            if (String.isBlank(template.ParsedFieldsJSON__c)) {
                throw new DocumentMergeException(
                    'Template "' + template.Name + '" must be validated before use. ' +
                    'ParsedFieldsJSON is empty. Please validate the template first.'
                );
            }
            
            // Fetch record data with optimized query (will fail fast if invalid)
            // Pass template ID to include bind variable fields from data sources
            SObject record = DataProviderService.fetchRecordDataOptimized(
                request.recordId, 
                template.ObjectApiName__c,
                template.ParsedFieldsJSON__c,
                template.Id  // Include bind variable fields from TemplateDataSource__c
            );
            
            // Build GAS request
            GASDocumentService.GenerationRequest gasRequest = buildGASRequest(
                template, record, request
            );
            
            // Debug: Log child data keys (relationships found)
            System.debug(LoggingLevel.INFO, '=== CHILD DATA RELATIONSHIPS: ' + gasRequest.childData.keySet() + ' ===');
            
            // Call GAS to generate document (CALLOUT - no DML before this!)
            GASDocumentService.GenerationResponse gasResponse = 
                GASDocumentService.generateDocument(gasRequest);
            
            if (!gasResponse.success) {
                throw new DocumentMergeException(gasResponse.errorMessage);
            }
            
            // Add any warnings from GAS
            result.warnings.addAll(gasResponse.warnings);
            result.generatedFileName = gasResponse.fileName;
            
            // PRODUCTION: Direct upload is the only supported path
            // GAS uploads PDF directly to Salesforce via JWT authentication
            if (request.attachToRecord) {
                if (gasResponse.uploadedDirectly && gasResponse.contentDocumentId != null) {
                    result.contentDocumentId = gasResponse.contentDocumentId;
                    result.contentVersionId = gasResponse.contentVersionId;
                    System.debug(LoggingLevel.INFO, '=== Direct upload successful: ' + result.contentDocumentId + ' ===');
                } else {
                    throw new DocumentMergeException(
                        'GAS did not return ContentDocumentId. ' +
                        'Ensure Salesforce JWT authentication is configured in GAS Script Properties. ' +
                        'Run testSalesforceAuth() in GAS to verify configuration.'
                    );
                }
            }
            
            result.success = true;
            result.durationMs = System.currentTimeMillis() - startTime;
            
            // Create log record AFTER all callouts complete
            createLogRecord(request, template, result);
            
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage() + '\n' + e.getStackTraceString();
            result.durationMs = System.currentTimeMillis() - startTime;
            
            // Create error log record (safe - callouts are done)
            createErrorLogRecord(request, template, result);
            
            System.debug(LoggingLevel.ERROR, 'Document generation failed: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, e.getStackTraceString());
        }
        
        return result;
    }
    
    /**
     * @description Generates documents for multiple records asynchronously
     * @param recordIds List of record IDs
     * @param templateName Template developer name
     * @return Id The async job ID
     */
    public static Id generateDocumentsAsync(List<Id> recordIds, String templateName) {
        return DocumentGenerationQueueable.enqueueMultiple(recordIds, templateName);
    }
    
    /**
     * @description Generates a single document asynchronously (for trigger context)
     * @param recordId Record ID
     * @param templateName Template developer name
     * @return Id The async job ID
     */
    public static Id generateDocumentAsync(Id recordId, String templateName) {
        return DocumentGenerationQueueable.enqueue(recordId, templateName);
    }
    
    /**
     * @description Validates the document generation request
     */
    private static void validateRequest(DocumentRequest request) {
        if (request == null) {
            throw new DocumentMergeException('Document request cannot be null');
        }
        if (request.recordId == null) {
            throw new DocumentMergeException('Record ID is required');
        }
        
        // Validate GAS configuration
        List<String> configErrors = GoogleAuthService.validateConfiguration();
        if (!configErrors.isEmpty()) {
            throw new DocumentMergeException('Configuration error: ' + String.join(configErrors, '; '));
        }
    }
    
    /**
     * @description Gets the template configuration from custom object
     */
    private static DocumentTemplate__c getTemplate(String templateName, Id recordId) {
        if (String.isNotBlank(templateName)) {
            List<DocumentTemplate__c> templates = [
                SELECT Id, Name, ObjectApiName__c, GoogleDocId__c,
                       Description__c, IsActive__c, OutputFileName__c, SortOrder__c,
                       ParsedFieldsJSON__c, ValidationStatus__c, LastValidated__c
                FROM DocumentTemplate__c
                WHERE Name = :templateName
                AND IsActive__c = true
                WITH USER_MODE
                LIMIT 1
            ];
            
            if (templates.isEmpty()) {
                throw new DocumentMergeException('Template not found or inactive: ' + templateName);
            }
            
            return templates[0];
        }
        
        // Auto-detect template by object type
        String objectApiName = recordId.getSObjectType().getDescribe().getName();
        
        List<DocumentTemplate__c> templates = [
            SELECT Id, Name, ObjectApiName__c, GoogleDocId__c,
                   Description__c, IsActive__c, OutputFileName__c, SortOrder__c,
                   ParsedFieldsJSON__c, ValidationStatus__c, LastValidated__c
            FROM DocumentTemplate__c
            WHERE ObjectApiName__c = :objectApiName
            AND IsActive__c = true
            WITH USER_MODE
            ORDER BY SortOrder__c ASC NULLS LAST
            LIMIT 1
        ];
        
        if (templates.isEmpty()) {
            throw new DocumentMergeException('No active template found for object: ' + objectApiName);
        }
        
        return templates[0];
    }
    
    /**
     * @description Builds the GAS request with all necessary data
     */
    private static GASDocumentService.GenerationRequest buildGASRequest(
        DocumentTemplate__c template, 
        SObject record, 
        DocumentRequest request
    ) {
        GASDocumentService.GenerationRequest gasRequest = new GASDocumentService.GenerationRequest();
        
        gasRequest.templateId = template.GoogleDocId__c;
        
        // Clear field types cache for this request
        collectedFieldTypes = new Map<String, String>();
        
        // Parse the template fields if not already parsed
        TemplateFieldParser.ParseResult parsedFields;
        if (String.isNotBlank(template.ParsedFieldsJSON__c)) {
            parsedFields = TemplateFieldParser.fromJSON(template.ParsedFieldsJSON__c);
        } else {
            // Fallback: empty parsed fields (should not happen if template is validated)
            parsedFields = new TemplateFieldParser.ParseResult();
        }
        
        // Build record data map first (needed for filename resolution and data source queries)
        // This also collects field types from schema - ONLY for fields in the template
        gasRequest.recordData = buildRecordDataMapWithTypes(record, template.ObjectApiName__c, parsedFields);
        
        // Build child data maps with nested children support
        // Also collects field types for child objects
        gasRequest.childData = buildChildDataMapsWithNestingAndTypes(record, template.ObjectApiName__c);
        
        // Add system variables
        gasRequest.systemVariables = buildSystemVariables(record.Id);
        
        // Fetch data source data (from TemplateDataSource__c records)
        gasRequest.crossObjectData = DataProviderService.fetchDataSourceData(
            template.Id,
            gasRequest.recordData
        );
        
        if (!gasRequest.crossObjectData.isEmpty()) {
            System.debug(LoggingLevel.INFO, '=== DATA SOURCE ALIASES: ' + gasRequest.crossObjectData.keySet() + ' ===');
        }
        
        // Resolve output filename - replace merge fields like {{QuoteNumber}}
        String fileNameTemplate = String.isNotBlank(request.outputFileName) 
            ? request.outputFileName 
            : template.OutputFileName__c;
        gasRequest.outputFileName = resolveFileName(fileNameTemplate, gasRequest.recordData, gasRequest.systemVariables);
        
        // Add additional merge fields
        if (request.additionalMergeFields != null) {
            gasRequest.additionalFields = request.additionalMergeFields;
        }
        
        // Add collected field types to record data for auto-formatting in GAS
        if (!collectedFieldTypes.isEmpty()) {
            gasRequest.recordData.put('_fieldTypes', collectedFieldTypes);
            System.debug(LoggingLevel.INFO, '=== FIELD TYPES COLLECTED: ' + collectedFieldTypes.size() + ' fields ===');
        }
        
        // Enable direct upload if configured
        // Direct upload bypasses Apex heap limits by having GAS upload directly to Salesforce
        gasRequest.useDirectUpload = isDirectUploadEnabled();
        gasRequest.parentRecordId = request.recordId;
        
        return gasRequest;
    }
    
    /**
     * @description Direct upload is always enabled (production requirement)
     * GAS must have Salesforce JWT auth configured - there is no Base64 fallback
     * @return Boolean Always returns true
     */
    private static Boolean isDirectUploadEnabled() {
        // PRODUCTION: Direct upload is the only supported path
        // GAS must have SF_CONSUMER_KEY, SF_USERNAME, SF_LOGIN_URL, SF_PRIVATE_KEY configured
        return true;
    }
    
    /**
     * @description Resolves merge fields in the output filename
     * Supports {{FieldName}} and {{Related.FieldName}} syntax
     */
    private static String resolveFileName(String fileNameTemplate, Map<String, Object> recordData, Map<String, Object> systemVars) {
        if (String.isBlank(fileNameTemplate)) {
            return 'Document_' + DateTime.now().getTime();
        }
        
        String resolved = fileNameTemplate;
        
        // Pattern: {{FieldName}} or {{Object.Field}}
        Pattern p = Pattern.compile('\\{\\{([^}]+)\\}\\}');
        Matcher m = p.matcher(resolved);
        
        while (m.find()) {
            String fullMatch = m.group(0);  // {{FieldName}}
            String fieldPath = m.group(1).trim();  // FieldName
            
            String replacement = '';
            
            // Check record data first
            if (recordData.containsKey(fieldPath)) {
                Object value = recordData.get(fieldPath);
                replacement = value != null ? String.valueOf(value) : '';
            }
            // Check system variables
            else if (systemVars.containsKey(fieldPath)) {
                Object value = systemVars.get(fieldPath);
                replacement = value != null ? String.valueOf(value) : '';
            }
            // Check nested system variables (e.g., CURRENT_USER.Name)
            else if (fieldPath.contains('.')) {
                List<String> parts = fieldPath.split('\\.');
                if (parts.size() == 2 && systemVars.containsKey(parts[0])) {
                    Object parent = systemVars.get(parts[0]);
                    if (parent instanceof Map<String, Object>) {
                        Map<String, Object> parentMap = (Map<String, Object>) parent;
                        if (parentMap.containsKey(parts[1])) {
                            Object value = parentMap.get(parts[1]);
                            replacement = value != null ? String.valueOf(value) : '';
                        }
                    }
                }
            }
            
            resolved = resolved.replace(fullMatch, replacement);
        }
        
        // Sanitize filename
        resolved = sanitizeFileName(resolved);
        
        return resolved;
    }
    
    /**
     * @description Sanitizes a string for use as a filename
     */
    private static String sanitizeFileName(String fileName) {
        if (String.isBlank(fileName)) {
            return 'Document_' + DateTime.now().getTime();
        }
        
        // Remove invalid filename characters
        fileName = fileName.replaceAll('[\\\\/:*?"<>|]', '_');
        
        // Replace multiple underscores/spaces with single underscore
        fileName = fileName.replaceAll('[_\\s]+', '_');
        
        // Remove leading/trailing underscores
        fileName = fileName.replaceAll('^_+|_+$', '');
        
        // Limit length
        if (fileName.length() > 150) {
            fileName = fileName.substring(0, 150);
        }
        
        // Ensure we have something
        if (String.isBlank(fileName)) {
            fileName = 'Document_' + DateTime.now().getTime();
        }
        
        return fileName;
    }
    
    /**
     * @description Builds record data map while also collecting field types from schema
     * This enables auto-formatting in GAS based on Salesforce field types
     * OPTIMIZED: Only collects types for fields actually in the template
     */
    private static Map<String, Object> buildRecordDataMapWithTypes(SObject record, String objectApiName, TemplateFieldParser.ParseResult parsedFields) {
        // Only collect field types for fields actually in the template
        collectFieldTypesFromParsedFields(objectApiName, parsedFields);
        
        // Build the data map recursively
        return buildRecordDataMapWithTypesRecursive(record, objectApiName, '', 0);
    }
    
    /**
     * @description Collects field types only for fields referenced in the template
     * This drastically reduces payload size compared to collecting all fields
     */
    private static void collectFieldTypesFromParsedFields(String objectApiName, TemplateFieldParser.ParseResult parsedFields) {
        Map<String, Schema.SObjectField> fieldMap = SchemaCache.getFieldMap(objectApiName);
        if (fieldMap == null) {
            return;
        }
        
        // Collect types for main object fields
        for (TemplateFieldParser.ParsedField field : parsedFields.mainObjectFields) {
            if (String.isNotBlank(field.fieldName) && fieldMap.containsKey(field.fieldName.toLowerCase())) {
                Schema.DescribeFieldResult fieldDesc = fieldMap.get(field.fieldName.toLowerCase()).getDescribe();
                String formatType = mapDisplayTypeToFormat(fieldDesc.getType());
                if (String.isNotBlank(formatType)) {
                    collectedFieldTypes.put(field.fieldName, formatType);
                }
            }
        }
        
        // Collect types for parent relationship fields
        for (TemplateFieldParser.ParsedField field : parsedFields.parentRelationshipFields) {
            if (String.isNotBlank(field.relationshipPath)) {
                collectFieldTypeForPath(objectApiName, field.relationshipPath);
            }
        }
        
        // Collect types for child relationships
        for (TemplateFieldParser.ParsedField childRel : parsedFields.childRelationships) {
            String childObjectName = TemplateFieldParser.getChildObjectName(objectApiName, childRel.fieldName);
            if (String.isNotBlank(childObjectName)) {
                collectFieldTypesForChildFromParsedFields(childObjectName, childRel);
            }
        }
    }
    
    /**
     * @description Collects field type for a relationship path like "Account.Owner.Name"
     */
    private static void collectFieldTypeForPath(String startObjectName, String relationshipPath) {
        List<String> parts = relationshipPath.split('\\.');
        String currentObject = startObjectName;
        
        for (Integer i = 0; i < parts.size(); i++) {
            String fieldName = parts[i];
            Map<String, Schema.SObjectField> fieldMap = SchemaCache.getFieldMap(currentObject);
            
            if (fieldMap == null || !fieldMap.containsKey(fieldName.toLowerCase())) {
                return;
            }
            
            Schema.DescribeFieldResult fieldDesc = fieldMap.get(fieldName.toLowerCase()).getDescribe();
            
            // If last part in path, collect its type
            if (i == parts.size() - 1) {
                String formatType = mapDisplayTypeToFormat(fieldDesc.getType());
                if (String.isNotBlank(formatType)) {
                    collectedFieldTypes.put(relationshipPath, formatType);
                }
            } else {
                // Navigate to related object
                Schema.sObjectType[] refs = fieldDesc.getReferenceTo();
                if (refs != null && refs.size() > 0) {
                    currentObject = refs[0].getDescribe().getName();
                } else {
                    return;
                }
            }
        }
    }
    
    /**
     * @description Collects field types for child relationship fields from parsed template
     */
    private static void collectFieldTypesForChildFromParsedFields(String childObjectName, TemplateFieldParser.ParsedField childRel) {
        Map<String, Schema.SObjectField> childFieldMap = SchemaCache.getFieldMap(childObjectName);
        if (childFieldMap == null) {
            return;
        }
        
        String relationshipPrefix = childRel.fieldName + '.';
        
        // Collect types for direct child fields
        for (TemplateFieldParser.ParsedField childField : childRel.childFields) {
            if (childField.fieldType == TemplateFieldParser.FieldType.MAIN_OBJECT) {
                if (String.isNotBlank(childField.fieldName) && childFieldMap.containsKey(childField.fieldName.toLowerCase())) {
                    Schema.DescribeFieldResult fieldDesc = childFieldMap.get(childField.fieldName.toLowerCase()).getDescribe();
                    String formatType = mapDisplayTypeToFormat(fieldDesc.getType());
                    if (String.isNotBlank(formatType)) {
                        collectedFieldTypes.put(relationshipPrefix + childField.fieldName, formatType);
                    }
                }
            } else if (childField.fieldType == TemplateFieldParser.FieldType.PARENT_RELATIONSHIP) {
                // Handle nested relationships within child (e.g., OpportunityLineItems.Product2.Name)
                if (String.isNotBlank(childField.relationshipPath)) {
                    String fullPath = relationshipPrefix + childField.relationshipPath;
                    collectFieldTypeForPath(childObjectName, childField.relationshipPath);
                    // Re-key with full path including child relationship
                    if (collectedFieldTypes.containsKey(childField.relationshipPath)) {
                        String formatType = collectedFieldTypes.get(childField.relationshipPath);
                        collectedFieldTypes.put(fullPath, formatType);
                    }
                }
            }
        }
        
        // Collect types for nested children (grandchildren)
        if (childRel.nestedChildren != null) {
            for (TemplateFieldParser.ParsedField nestedChild : childRel.nestedChildren) {
                String grandchildObjectName = TemplateFieldParser.getChildObjectName(childObjectName, nestedChild.fieldName);
                if (String.isNotBlank(grandchildObjectName)) {
                    collectFieldTypesForChildFromParsedFields(grandchildObjectName, nestedChild);
                }
            }
        }
    }
    
    /**
     * @description Recursively builds record data map and collects field types
     */
    private static Map<String, Object> buildRecordDataMapWithTypesRecursive(
        SObject record, 
        String objectApiName, 
        String prefix, 
        Integer depth
    ) {
        Map<String, Object> dataMap = new Map<String, Object>();
        
        if (record == null || depth > MAX_RELATIONSHIP_DEPTH) {
            return dataMap;
        }
        
        Map<String, Object> populatedFields = record.getPopulatedFieldsAsMap();
        Map<String, Schema.SObjectField> fieldMap = SchemaCache.getFieldMap(objectApiName);
        
        for (String fieldName : populatedFields.keySet()) {
            Object value = populatedFields.get(fieldName);
            
            // Skip child relationships (List) - handled separately
            if (value instanceof List<Object>) {
                continue;
            }
            
            // Handle related objects recursively
            if (value instanceof SObject) {
                SObject relatedRecord = (SObject) value;
                String relatedObjectName = getRelatedObjectName(fieldMap, fieldName);
                
                if (String.isNotBlank(relatedObjectName)) {
                    String newPrefix = String.isBlank(prefix) ? fieldName : prefix + '.' + fieldName;
                    // Field types are now collected upfront from parsed template
                    // No need to collect here during data building
                    
                    Map<String, Object> nestedMap = buildRecordDataMapWithTypesRecursive(
                        relatedRecord, relatedObjectName, newPrefix, depth + 1
                    );
                    if (!nestedMap.isEmpty()) {
                        dataMap.put(fieldName, nestedMap);
                    }
                }
            } else {
                dataMap.put(fieldName, value);
            }
        }
        
        return dataMap;
    }
    
    /**
     * @description Gets the related object name for a relationship field
     */
    private static String getRelatedObjectName(Map<String, Schema.SObjectField> fieldMap, String relationshipName) {
        // The relationship name in populated fields is like "Account" but the field is "AccountId"
        String lookupFieldName = relationshipName + 'Id';
        
        if (fieldMap.containsKey(lookupFieldName.toLowerCase())) {
            Schema.DescribeFieldResult fieldDesc = fieldMap.get(lookupFieldName.toLowerCase()).getDescribe();
            List<Schema.SObjectType> refs = fieldDesc.getReferenceTo();
            if (!refs.isEmpty()) {
                return refs[0].getDescribe().getName();
            }
        }
        
        // Try without Id suffix (for polymorphic or special relationships)
        for (String key : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDesc = fieldMap.get(key).getDescribe();
            if (fieldDesc.getRelationshipName() == relationshipName) {
                List<Schema.SObjectType> refs = fieldDesc.getReferenceTo();
                if (!refs.isEmpty()) {
                    return refs[0].getDescribe().getName();
                }
            }
        }
        
        return null;
    }
    
    /**
     * @description Maps Salesforce DisplayType to format string for GAS
     */
    private static String mapDisplayTypeToFormat(Schema.DisplayType displayType) {
        switch on displayType {
            when CURRENCY {
                return 'CURRENCY';
            }
            when PERCENT {
                return 'PERCENT';
            }
            when DATE {
                return 'DATE';
            }
            when DATETIME {
                return 'DATETIME';
            }
            when TIME {
                return 'TIME';
            }
            when PHONE {
                return 'PHONE';
            }
            when BOOLEAN {
                return 'BOOLEAN';
            }
            when DOUBLE, INTEGER, LONG {
                return 'NUMBER';
            }
            when EMAIL {
                return 'EMAIL';
            }
            when URL {
                return 'URL';
            }
            when else {
                return null;
            }
        }
    }
    
    private static final Integer MAX_RELATIONSHIP_DEPTH = 5;
    
    // Cache for field types collected during data building
    private static Map<String, String> collectedFieldTypes = new Map<String, String>();
    
    /**
     * @description Builds maps of child record data with types collection
     */
    private static Map<String, List<Map<String, Object>>> buildChildDataMapsWithNestingAndTypes(SObject record, String parentObjectApiName) {
        Map<String, List<Map<String, Object>>> childData = new Map<String, List<Map<String, Object>>>();
        
        Map<String, Object> populatedFields = record.getPopulatedFieldsAsMap();
        
        // Get child relationships to find child object names
        Map<String, String> childRelationshipToObject = getChildRelationshipObjectMap(parentObjectApiName);
        
        for (String fieldName : populatedFields.keySet()) {
            Object value = populatedFields.get(fieldName);
            
            if (!(value instanceof List<Object>)) {
                continue;
            }
            
            List<Object> childObjects = (List<Object>) value;
            if (childObjects.isEmpty() || !(childObjects[0] instanceof SObject)) {
                continue;
            }
            
            // Field types are now collected upfront from parsed template
            // No need to collect here during data building
            
            // Get child object name for record map building
            String childObjectName = childRelationshipToObject.get(fieldName);
            
            List<Map<String, Object>> childList = new List<Map<String, Object>>();
            
            for (Object childObj : childObjects) {
                SObject childRecord = (SObject) childObj;
                Map<String, Object> childMap = buildSingleChildRecordMapWithTypes(childRecord, childObjectName, fieldName);
                childList.add(childMap);
            }
            
            if (!childList.isEmpty()) {
                childData.put(fieldName, childList);
            }
        }
        
        return childData;
    }
    
    /**
     * @description Gets a map of child relationship names to child object API names
     */
    private static Map<String, String> getChildRelationshipObjectMap(String parentObjectApiName) {
        Map<String, String> relationshipMap = new Map<String, String>();
        
        List<Schema.ChildRelationship> childRels = SchemaCache.getChildRelationships(parentObjectApiName);
        
        for (Schema.ChildRelationship rel : childRels) {
            String relName = rel.getRelationshipName();
            if (String.isNotBlank(relName)) {
                relationshipMap.put(relName, rel.getChildSObject().getDescribe().getName());
            }
        }
        
        return relationshipMap;
    }
    
    /**
     * @description Builds a map for a single child record with type collection for nested lookups
     * Note: Field types are now collected upfront from parsed template, not during data building
     */
    private static Map<String, Object> buildSingleChildRecordMapWithTypes(SObject childRecord, String childObjectName, String relationshipName) {
        Map<String, Object> childMap = new Map<String, Object>();
        Map<String, Object> childFields = childRecord.getPopulatedFieldsAsMap();
        Map<String, Schema.SObjectField> fieldMap = String.isNotBlank(childObjectName) ? 
            SchemaCache.getFieldMap(childObjectName) : null;
        
        for (String childFieldName : childFields.keySet()) {
            Object childValue = childFields.get(childFieldName);
            
            // Handle nested child relationships (grandchildren)
            if (childValue instanceof List<Object>) {
                List<Object> grandchildObjects = (List<Object>) childValue;
                if (!grandchildObjects.isEmpty() && grandchildObjects[0] instanceof SObject) {
                    List<Map<String, Object>> grandchildList = new List<Map<String, Object>>();
                    for (Object grandchildObj : grandchildObjects) {
                        SObject grandchildRecord = (SObject) grandchildObj;
                        Map<String, Object> grandchildMap = buildSingleChildRecordMap(grandchildRecord);
                        grandchildList.add(grandchildMap);
                    }
                    
                    if (!grandchildList.isEmpty()) {
                        childMap.put(childFieldName, grandchildList);
                    }
                }
                continue;
            }
            
            // Handle nested related objects (lookups like Product2)
            if (childValue instanceof SObject) {
                SObject nestedRecord = (SObject) childValue;
                
                // Field types are now collected upfront from parsed template
                // No need to collect here during data building
                
                Map<String, Object> nestedFields = nestedRecord.getPopulatedFieldsAsMap();
                Map<String, Object> nestedMap = new Map<String, Object>();
                
                for (String nestedField : nestedFields.keySet()) {
                    Object nestedValue = nestedFields.get(nestedField);
                    if (!(nestedValue instanceof SObject) && !(nestedValue instanceof List<Object>)) {
                        nestedMap.put(nestedField, nestedValue);
                    }
                }
                
                if (!nestedMap.isEmpty()) {
                    childMap.put(childFieldName, nestedMap);
                }
            } else {
                childMap.put(childFieldName, childValue);
            }
        }
        
        return childMap;
    }
    
    /**
     * @description Builds a map for a single child record (simple version)
     */
    private static Map<String, Object> buildSingleChildRecordMap(SObject childRecord) {
        Map<String, Object> childMap = new Map<String, Object>();
        Map<String, Object> childFields = childRecord.getPopulatedFieldsAsMap();
        
        for (String childFieldName : childFields.keySet()) {
            Object childValue = childFields.get(childFieldName);
            
            // Handle nested child relationships (grandchildren)
            if (childValue instanceof List<Object>) {
                List<Object> grandchildObjects = (List<Object>) childValue;
                if (!grandchildObjects.isEmpty() && grandchildObjects[0] instanceof SObject) {
                    List<Map<String, Object>> grandchildList = new List<Map<String, Object>>();
                    for (Object grandchildObj : grandchildObjects) {
                        SObject grandchildRecord = (SObject) grandchildObj;
                        Map<String, Object> grandchildMap = buildSingleChildRecordMap(grandchildRecord);
                        grandchildList.add(grandchildMap);
                    }
                    
                    if (!grandchildList.isEmpty()) {
                        childMap.put(childFieldName, grandchildList);
                    }
                }
                continue;
            }
            
            // Handle nested related objects in child records (e.g., Product2 lookup)
            if (childValue instanceof SObject) {
                SObject nestedRecord = (SObject) childValue;
                Map<String, Object> nestedFields = nestedRecord.getPopulatedFieldsAsMap();
                Map<String, Object> nestedMap = new Map<String, Object>();
                
                for (String nestedField : nestedFields.keySet()) {
                    Object nestedValue = nestedFields.get(nestedField);
                    if (!(nestedValue instanceof SObject) && !(nestedValue instanceof List<Object>)) {
                        nestedMap.put(nestedField, nestedValue);
                    }
                }
                
                if (!nestedMap.isEmpty()) {
                    childMap.put(childFieldName, nestedMap);
                }
            } else {
                childMap.put(childFieldName, childValue);
            }
        }
        
        return childMap;
    }
    
    /**
     * @description Builds system variables map
     */
    private static Map<String, Object> buildSystemVariables(Id recordId) {
        Map<String, Object> sysVars = new Map<String, Object>();
        
        // Date/Time variables
        sysVars.put('TODAY', Date.today().format());
        sysVars.put('NOW', DateTime.now().format());
        sysVars.put('TIMESTAMP', DateTime.now().getTime());
        sysVars.put('RECORD_ID', String.valueOf(recordId));
        
        // Current user variables
        sysVars.put('CURRENT_USER', new Map<String, Object>{
            'Id' => UserInfo.getUserId(),
            'Name' => UserInfo.getName(),
            'FirstName' => UserInfo.getFirstName(),
            'LastName' => UserInfo.getLastName(),
            'Email' => UserInfo.getUserEmail()
        });
        
        // Organization variables
        try {
            Organization org = [
                SELECT Id, Name, Street, City, State, PostalCode, Country, Phone
                FROM Organization 
                LIMIT 1
            ];
            sysVars.put('ORG', new Map<String, Object>{
                'Name' => org.Name,
                'Street' => org.Street,
                'City' => org.City,
                'State' => org.State,
                'PostalCode' => org.PostalCode,
                'Country' => org.Country,
                'Phone' => org.Phone
            });
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Could not query Organization: ' + e.getMessage());
        }
        
        return sysVars;
    }
    
    /**
     * @description Generates default file name using dynamic name field detection
     */
    private static String generateDefaultFileName(DocumentTemplate__c template, SObject record) {
        String objectName = template.ObjectApiName__c;
        
        String recordName = '';
        Map<String, Object> fields = record.getPopulatedFieldsAsMap();
        
        String nameField = DataProviderService.getNameFieldForObject(objectName);
        if (String.isNotBlank(nameField) && fields.containsKey(nameField)) {
            recordName = String.valueOf(fields.get(nameField));
        }
        
        if (String.isBlank(recordName)) {
            recordName = String.valueOf(record.Id);
        }
        
        // Sanitize for filename
        recordName = recordName.replaceAll('[^a-zA-Z0-9]', '_');
        if (recordName.length() > 50) {
            recordName = recordName.substring(0, 50);
        }
        
        return objectName + '_' + recordName + '_' + Date.today().format().replaceAll('/', '-') + '.pdf';
    }
    
    /**
     * @description Creates a success log record (called AFTER callouts)
     */
    private static void createLogRecord(DocumentRequest request, DocumentTemplate__c template, DocumentResult result) {
        if (!GoogleAuthService.isLoggingEnabled() || template == null) {
            return;
        }
        
        try {
            DocumentGenerationLog__c log = new DocumentGenerationLog__c();
            log.RecordId__c = String.valueOf(request.recordId);
            log.ObjectApiName__c = template.ObjectApiName__c;
            log.TemplateName__c = template.Name;
            log.Status__c = result.hasWarnings() ? 'Success with Warnings' : 'Success';
            log.ContentDocumentId__c = result.contentDocumentId != null ? String.valueOf(result.contentDocumentId) : null;
            log.DurationMs__c = result.durationMs;
            log.GeneratedBy__c = UserInfo.getUserId();
            
            if (result.hasWarnings()) {
                log.ErrorMessage__c = 'Warnings: ' + String.join(result.warnings, '; ');
            }
            
            Database.insert(log, false);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to create log record: ' + e.getMessage());
        }
    }
    
    /**
     * @description Creates an error log record (called AFTER callouts)
     */
    private static void createErrorLogRecord(DocumentRequest request, DocumentTemplate__c template, DocumentResult result) {
        if (!GoogleAuthService.isLoggingEnabled()) {
            return;
        }
        
        try {
            DocumentGenerationLog__c log = new DocumentGenerationLog__c();
            log.RecordId__c = request != null ? String.valueOf(request.recordId) : null;
            if (template != null) {
                log.ObjectApiName__c = template.ObjectApiName__c;
            } else if (request != null && request.recordId != null) {
                log.ObjectApiName__c = request.recordId.getSObjectType().getDescribe().getName();
            }
            log.TemplateName__c = template != null ? template.Name : null;
            log.Status__c = 'Failed';
            log.ErrorMessage__c = result.errorMessage;
            log.DurationMs__c = result.durationMs;
            log.GeneratedBy__c = UserInfo.getUserId();
            
            Database.insert(log, false);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to create error log record: ' + e.getMessage());
        }
    }
}
