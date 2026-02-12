/**
 * @description Service for validating Google Doc templates and updating DocumentTemplate__c records.
 * Orchestrates the validation process by calling GAS, parsing fields, and storing results.
 * 
 * Validation includes:
 * - Fetching template text from Google Docs via GAS
 * - Parsing merge fields, relationships, and sections
 * - Validating fields against Salesforce schema (FAIL FAST on invalid fields)
 * - Validating TemplateDataSource__c configurations
 * 
 * @author Document Generation Framework
 * @since 2024
 */
public with sharing class TemplateValidationService {
    
    /**
     * @description Exception for validation errors
     */
    public class ValidationException extends Exception {}
    
    /**
     * @description Result of template validation
     */
    public class ValidationResult {
        public Boolean isSuccess { get; set; }
        public String status { get; set; }
        public List<String> errors { get; set; }
        public List<String> warnings { get; set; }
        public String parsedFieldsJSON { get; set; }
        public Integer mainObjectFieldCount { get; set; }
        public Integer parentRelationshipCount { get; set; }
        public Integer childRelationshipCount { get; set; }
        public Integer dataSourceCount { get; set; }
        public Integer nestedChildCount { get; set; }
        
        public ValidationResult() {
            this.isSuccess = false;
            this.errors = new List<String>();
            this.warnings = new List<String>();
            this.dataSourceCount = 0;
            this.nestedChildCount = 0;
        }
    }
    
    /**
     * @description Validates a template and updates the DocumentTemplate__c record
     * @param templateId The DocumentTemplate__c record ID
     * @return ValidationResult The validation result
     */
    public static ValidationResult validateAndUpdateTemplate(Id templateId) {
        ValidationResult result = new ValidationResult();
        
        try {
            // Get template record
            DocumentTemplate__c template = getTemplateRecord(templateId);
            
            // Get data source aliases for this template
            Set<String> dataSourceAliases = getDataSourceAliases(templateId);
            result.dataSourceCount = dataSourceAliases.size();
            
            // Call GAS to get template text
            String templateText = fetchTemplateTextFromGAS(template.GoogleDocId__c);

            if (String.isBlank(templateText)) {
                throw new ValidationException('Could not fetch template text from Google Docs');
            }

            // Calculate checksum for staleness detection
            String newChecksum = calculateChecksum(templateText);
            Boolean checksumChanged = template.TemplateTextChecksum__c != newChecksum;

            if (checksumChanged && String.isNotBlank(template.TemplateTextChecksum__c)) {
                result.warnings.add('Template text has changed since last validation. Previous checksum: ' +
                                  template.TemplateTextChecksum__c + ', new: ' + newChecksum);
            }
            
            // Parse template fields with known data source aliases
            TemplateFieldParser.ParseResult parseResult = TemplateFieldParser.parseTemplateWithDataSources(
                templateText, 
                template.ObjectApiName__c,
                dataSourceAliases
            );
            
            // Check for parse errors
            if (!parseResult.errors.isEmpty()) {
                result.isSuccess = false;
                result.status = 'Error';
                result.errors.addAll(parseResult.errors);
                
                // Update template with error status (no checksum for error case)
                updateTemplateRecord(template, result, parseResult, null);
                return result;
            }
            
            // Validate fields against schema (FAIL FAST on invalid fields)
            validateFieldsAgainstSchema(parseResult, template.ObjectApiName__c, result);
            
            // Validate data source configurations
            validateDataSources(templateId, parseResult, result);
            
            // Set success status
            if (result.errors.isEmpty()) {
                result.isSuccess = true;
                result.status = result.warnings.isEmpty() ? 'Valid' : 'Warning';
            } else {
                result.isSuccess = false;
                result.status = 'Error';
            }
            
            // Add warnings from parse result
            result.warnings.addAll(parseResult.warnings);
            
            // Store counts
            result.mainObjectFieldCount = parseResult.mainObjectFields.size();
            result.parentRelationshipCount = parseResult.parentRelationshipFields.size();
            result.childRelationshipCount = parseResult.childRelationships.size();
            result.nestedChildCount = countNestedChildren(parseResult.childRelationships);
            
            // Convert to JSON for storage
            result.parsedFieldsJSON = parseResult.toJSON();

            // Update template record with new checksum
            updateTemplateRecord(template, result, parseResult, newChecksum);
            
        } catch (Exception e) {
            result.isSuccess = false;
            result.status = 'Error';
            result.errors.add('Validation failed: ' + e.getMessage());
        }
        
        return result;
    }
    
    /**
     * @description Validates multiple templates
     * @param templateIds List of DocumentTemplate__c record IDs
     * @return Map<Id, ValidationResult> Results keyed by template ID
     */
    public static Map<Id, ValidationResult> validateMultipleTemplates(List<Id> templateIds) {
        Map<Id, ValidationResult> results = new Map<Id, ValidationResult>();
        
        for (Id templateId : templateIds) {
            try {
                ValidationResult result = validateAndUpdateTemplate(templateId);
                results.put(templateId, result);
            } catch (Exception e) {
                ValidationResult errorResult = new ValidationResult();
                errorResult.isSuccess = false;
                errorResult.status = 'Error';
                errorResult.errors.add('Validation failed: ' + e.getMessage());
                results.put(templateId, errorResult);
            }
        }
        
        return results;
    }
    
    /**
     * @description Gets the set of data source aliases for a template
     */
    private static Set<String> getDataSourceAliases(Id templateId) {
        Set<String> aliases = new Set<String>();
        
        List<TemplateDataSource__c> dataSources = [
            SELECT Alias__c
            FROM TemplateDataSource__c
            WHERE DocumentTemplate__c = :templateId
            AND IsActive__c = true
            WITH USER_MODE
        ];
        
        for (TemplateDataSource__c ds : dataSources) {
            if (String.isNotBlank(ds.Alias__c)) {
                aliases.add(ds.Alias__c);
            }
        }
        
        return aliases;
    }
    
    /**
     * @description Fetches template text from GAS
     */
    private static String fetchTemplateTextFromGAS(String googleDocId) {
        // Call GAS validate action to get template content
        Map<String, Object> gasResult = GASDocumentService.validateTemplate(googleDocId);
        
        // Check if GAS returned the template text
        if (gasResult.containsKey('templateText')) {
            String templateText = (String) gasResult.get('templateText');
            if (String.isNotBlank(templateText)) {
                return templateText;
            }
        }
        
        // Provide detailed error message
        String errorMsg = 'GAS did not return template text. Please ensure:\n' +
                         '1. You have deployed the updated GAS middleware (TemplateProcessor.gs)\n' +
                         '2. The validateTemplate function includes: result.templateText = text;\n' +
                         '3. Your GAS deployment is accessible from Salesforce\n\n';
        
        if (gasResult.containsKey('error')) {
            errorMsg += 'GAS Error: ' + gasResult.get('error');
        } else if (gasResult.containsKey('success') && gasResult.get('success') == false) {
            errorMsg += 'GAS returned unsuccessful response';
        } else {
            errorMsg += 'Response received but templateText field is missing or empty.\n' +
                       'GAS Response keys: ' + String.join(new List<String>(gasResult.keySet()), ', ');
        }
        
        throw new ValidationException(errorMsg);
    }
    
    /**
     * @description Validates parsed fields against Salesforce schema.
     * Invalid fields are treated as ERRORS (fail fast) to prevent runtime failures.
     */
    private static void validateFieldsAgainstSchema(
        TemplateFieldParser.ParseResult parseResult, 
        String objectApiName,
        ValidationResult result
    ) {
        // Validate main object fields
        Map<String, Schema.SObjectField> fieldMap = SchemaCache.getFieldMap(objectApiName);

        for (TemplateFieldParser.ParsedField field : parseResult.mainObjectFields) {
            if (!fieldMap.containsKey(field.fieldName.toLowerCase())) {
                // Field does not exist
                if (String.isBlank(field.defaultValue)) {
                    // ERROR: Field missing and no default value provided
                    result.errors.add('Field not found on ' + objectApiName + ': ' + field.fieldName);
                } else {
                    // WARNING: Field missing but has default value (will use default at runtime)
                    result.warnings.add('Field not found on ' + objectApiName + ': ' + field.fieldName +
                                       ' (default value \'' + field.defaultValue + '\' will be used)');
                }
            } else {
                Schema.DescribeFieldResult fieldDesc = fieldMap.get(field.fieldName.toLowerCase()).getDescribe();
                if (!fieldDesc.isAccessible()) {
                    // ERROR: Field not accessible
                    result.errors.add('Field not accessible (check permissions): ' + objectApiName + '.' + field.fieldName);
                } else {
                    // Validate format directive compatibility
                    if (String.isNotBlank(field.formatDirective)) {
                        validateFormatDirective(field, fieldDesc, result);
                    }
                }
            }
        }
        
        // Validate parent relationship fields
        for (TemplateFieldParser.ParsedField field : parseResult.parentRelationshipFields) {
            validateRelationshipField(field, objectApiName, result);
        }
        
        // Validate child relationships with nested children support
        for (TemplateFieldParser.ParsedField childRel : parseResult.childRelationships) {
            validateChildRelationshipRecursive(childRel, objectApiName, result, 1);
        }
    }
    
    /**
     * @description Validates data source configurations
     */
    private static void validateDataSources(
        Id templateId,
        TemplateFieldParser.ParseResult parseResult,
        ValidationResult result
    ) {
        // Get all active data sources for this template
        List<TemplateDataSource__c> dataSources = [
            SELECT Id, Alias__c, ObjectApiName__c, FilterCondition__c, 
                   FieldList__c, OrderBy__c, RecordLimit__c
            FROM TemplateDataSource__c
            WHERE DocumentTemplate__c = :templateId
            AND IsActive__c = true
            WITH USER_MODE
        ];
        
        if (dataSources.isEmpty()) {
            // Check if template references any data source aliases
            if (!parseResult.dataSourceAliasesReferenced.isEmpty()) {
                for (String alias : parseResult.dataSourceAliasesReferenced) {
                    result.errors.add('Template references data source alias "' + alias + 
                                     '" but no TemplateDataSource__c record exists for it');
                }
            }
            return;
        }
        
        // Build set of configured aliases
        Set<String> configuredAliases = new Set<String>();
        
        // Validate each data source
        for (TemplateDataSource__c ds : dataSources) {
            configuredAliases.add(ds.Alias__c);
            
            List<String> dsErrors = CrossObjectQueryBuilder.validateDataSource(ds);
            
            for (String errorMsg : dsErrors) {
                result.errors.add('Data Source "' + ds.Alias__c + '": ' + errorMsg);
            }
        }
        
        // Check for referenced but unconfigured aliases
        for (String alias : parseResult.dataSourceAliasesReferenced) {
            if (!configuredAliases.contains(alias)) {
                result.errors.add('Template references data source alias "' + alias + 
                                 '" but no TemplateDataSource__c record exists for it');
            }
        }
        
        // Warn about configured but unreferenced data sources
        for (String alias : configuredAliases) {
            if (!parseResult.dataSourceAliasesReferenced.contains(alias)) {
                result.warnings.add('Data Source "' + alias + '" is configured but not referenced in the template');
            }
        }
    }
    
    /**
     * @description Recursively validates child relationships including nested children
     */
    private static void validateChildRelationshipRecursive(
        TemplateFieldParser.ParsedField childRel,
        String parentObjectName,
        ValidationResult result,
        Integer depth
    ) {
        // Check nesting depth limit
        if (depth > 2) {
            result.warnings.add('Nested child depth exceeds recommended limit (2 levels) for: ' + childRel.fieldName);
        }
        
        // Check if relationship exists
        if (!childRelationshipExists(parentObjectName, childRel.fieldName)) {
            result.errors.add('Child relationship not found: ' + childRel.fieldName + ' on ' + parentObjectName);
            return;
        }
        
        // Get child object name
        String childObjectName = TemplateFieldParser.getChildObjectName(parentObjectName, childRel.fieldName);
        
        if (String.isBlank(childObjectName)) {
            result.warnings.add('Could not determine child object for relationship: ' + childRel.fieldName);
            return;
        }
        
        // Validate fields within child relationship
        Map<String, Schema.SObjectField> childFieldMap = SchemaCache.getFieldMap(childObjectName);

        for (TemplateFieldParser.ParsedField childField : childRel.childFields) {
            if (childField.fieldType == TemplateFieldParser.FieldType.MAIN_OBJECT) {
                if (!childFieldMap.containsKey(childField.fieldName.toLowerCase())) {
                    // Field not found in child relationship
                    if (String.isBlank(childField.defaultValue)) {
                        // ERROR: Field missing and no default value
                        result.errors.add('Field not found on ' + childObjectName + ': ' + childField.fieldName +
                                         ' (in child relationship ' + childRel.fieldName + ')');
                    } else {
                        // WARNING: Field missing but has default value
                        result.warnings.add('Field not found on ' + childObjectName + ': ' + childField.fieldName +
                                           ' (in child relationship ' + childRel.fieldName + ') - default value \'' +
                                           childField.defaultValue + '\' will be used');
                    }
                } else {
                    // Validate format directive for child field
                    if (String.isNotBlank(childField.formatDirective)) {
                        Schema.DescribeFieldResult fieldDesc = childFieldMap.get(childField.fieldName.toLowerCase()).getDescribe();
                        validateFormatDirective(childField, fieldDesc, result);
                    }
                }
            } else if (childField.fieldType == TemplateFieldParser.FieldType.PARENT_RELATIONSHIP) {
                validateRelationshipField(childField, childObjectName, result);
            }
        }
        
        // Recursively validate nested children (grandchildren)
        if (childRel.nestedChildren != null && !childRel.nestedChildren.isEmpty()) {
            for (TemplateFieldParser.ParsedField nestedChild : childRel.nestedChildren) {
                validateChildRelationshipRecursive(nestedChild, childObjectName, result, depth + 1);
            }
        }
    }
    
    /**
     * @description Counts the total number of nested children
     */
    private static Integer countNestedChildren(List<TemplateFieldParser.ParsedField> childRelationships) {
        Integer count = 0;
        
        if (childRelationships == null) {
            return count;
        }
        
        for (TemplateFieldParser.ParsedField childRel : childRelationships) {
            if (childRel.nestedChildren != null) {
                count += childRel.nestedChildren.size();
                count += countNestedChildren(childRel.nestedChildren);
            }
        }
        
        return count;
    }
    
    /**
     * @description Validates a relationship field
     */
    private static void validateRelationshipField(
        TemplateFieldParser.ParsedField field,
        String objectApiName,
        ValidationResult result
    ) {
        String[] pathParts = field.relationshipPath.split('\\.');
        String currentObjectName = objectApiName;

        // Traverse the relationship path
        for (Integer i = 0; i < pathParts.size() - 1; i++) {
            String relationshipName = pathParts[i];

            Schema.SObjectType relatedObject = getRelatedObjectType(currentObjectName, relationshipName);

            if (relatedObject == null) {
                result.errors.add('Relationship not found: ' + relationshipName + ' on ' + currentObjectName +
                                 ' (in path: ' + field.relationshipPath + ')');
                return;
            }

            currentObjectName = relatedObject.getDescribe().getName();
        }

        // Validate the final field
        String finalField = pathParts[pathParts.size() - 1];
        Map<String, Schema.SObjectField> finalFieldMap = SchemaCache.getFieldMap(currentObjectName);

        if (!finalFieldMap.containsKey(finalField.toLowerCase())) {
            // Field not found in relationship path
            if (String.isBlank(field.defaultValue)) {
                // ERROR: Field missing and no default value
                result.errors.add('Field not found: ' + finalField + ' on ' + currentObjectName +
                                 ' (in path: ' + field.relationshipPath + ')');
            } else {
                // WARNING: Field missing but has default value
                result.warnings.add('Field not found: ' + finalField + ' on ' + currentObjectName +
                                   ' (in path: ' + field.relationshipPath + ') - default value \'' +
                                   field.defaultValue + '\' will be used');
            }
        } else {
            // Validate format directive for relationship field
            if (String.isNotBlank(field.formatDirective)) {
                Schema.DescribeFieldResult fieldDesc = finalFieldMap.get(finalField.toLowerCase()).getDescribe();
                validateFormatDirective(field, fieldDesc, result);
            }
        }
    }

    /**
     * @description Validates format directive compatibility with field type
     */
    private static void validateFormatDirective(
        TemplateFieldParser.ParsedField field,
        Schema.DescribeFieldResult fieldDesc,
        ValidationResult result
    ) {
        FormatValidationHelper.ValidationResult formatResult =
            FormatValidationHelper.validateFormatCompatibility(field.formatDirective, fieldDesc.getType());

        if (formatResult.hasError()) {
            result.errors.add('Format directive error for field "' + field.fieldName + '": ' + formatResult.errorMessage);
        } else if (formatResult.hasWarning()) {
            result.warnings.add('Format directive warning for field "' + field.fieldName + '": ' + formatResult.warningMessage);
        }

        // Additional check: warn about unrecognized formats
        if (!FormatValidationHelper.isRecognizedFormat(field.formatDirective)) {
            result.warnings.add('Format directive "' + field.formatDirective + '" is not recognized. ' +
                              'It may be custom or result in unexpected formatting.');
        }
    }
    
    /**
     * @description Gets the related object type for a relationship field
     */
    private static Schema.SObjectType getRelatedObjectType(String objectApiName, String relationshipName) {
        Map<String, Schema.SObjectField> fieldMap = SchemaCache.getFieldMap(objectApiName);
        
        for (Schema.SObjectField field : fieldMap.values()) {
            Schema.DescribeFieldResult fieldDesc = field.getDescribe();
            
            if (fieldDesc.getType() == Schema.DisplayType.REFERENCE && 
                fieldDesc.getRelationshipName() == relationshipName) {
                List<Schema.SObjectType> references = fieldDesc.getReferenceTo();
                if (!references.isEmpty()) {
                    return references[0];
                }
            }
        }
        
        return null;
    }
    
    /**
     * @description Checks if a child relationship exists
     */
    private static Boolean childRelationshipExists(String objectApiName, String relationshipName) {
        List<Schema.ChildRelationship> childRels = SchemaCache.getChildRelationships(objectApiName);
        
        for (Schema.ChildRelationship childRel : childRels) {
            if (childRel.getRelationshipName() == relationshipName) {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * @description Gets template record with required fields
     */
    private static DocumentTemplate__c getTemplateRecord(Id templateId) {
        List<DocumentTemplate__c> templates = [
            SELECT Id, Name, ObjectApiName__c, GoogleDocId__c,
                   ParsedFieldsJSON__c, ValidationStatus__c, ValidationMessage__c,
                   LastValidated__c, TemplateTextChecksum__c
            FROM DocumentTemplate__c
            WHERE Id = :templateId
            WITH USER_MODE
            LIMIT 1
        ];

        if (templates.isEmpty()) {
            throw new ValidationException('Template not found: ' + templateId);
        }

        return templates[0];
    }
    
    /**
     * @description Updates template record with validation results
     */
    private static void updateTemplateRecord(
        DocumentTemplate__c template,
        ValidationResult result,
        TemplateFieldParser.ParseResult parseResult,
        String newChecksum
    ) {
        template.ValidationStatus__c = result.status;
        template.LastValidated__c = DateTime.now();
        template.ParsedFieldsJSON__c = parseResult.toJSON();

        // Update checksum if provided
        if (String.isNotBlank(newChecksum)) {
            template.TemplateTextChecksum__c = newChecksum;
        }
        
        // Build validation message
        List<String> messages = new List<String>();
        
        if (!result.errors.isEmpty()) {
            messages.add('ERRORS:\n' + String.join(result.errors, '\n'));
        }
        if (!result.warnings.isEmpty()) {
            messages.add('WARNINGS:\n' + String.join(result.warnings, '\n'));
        }
        if (messages.isEmpty()) {
            String summary = 'Template validation successful.\n' +
                            'Fields: ' + parseResult.mainObjectFields.size() + ' main, ' +
                            parseResult.parentRelationshipFields.size() + ' parent relationships, ' +
                            parseResult.childRelationships.size() + ' child relationships';
            
            // Add data source count if any
            if (result.dataSourceCount > 0) {
                summary += ', ' + result.dataSourceCount + ' data sources';
            }
            
            // Add nested child count if any
            Integer nestedCount = countNestedChildren(parseResult.childRelationships);
            if (nestedCount > 0) {
                summary += ', ' + nestedCount + ' nested children (grandchildren)';
            }
            
            messages.add(summary);
        }
        
        template.ValidationMessage__c = String.join(messages, '\n\n');
        
        Database.update(template, false);
    }

    /**
     * @description Calculates MD5 checksum of template text for staleness detection
     * @param templateText The template text from Google Docs
     * @return String The MD5 checksum as hex string
     */
    private static String calculateChecksum(String templateText) {
        if (String.isBlank(templateText)) {
            return null;
        }

        Blob templateBlob = Blob.valueOf(templateText);
        Blob checksumBlob = Crypto.generateDigest('MD5', templateBlob);
        return EncodingUtil.convertToHex(checksumBlob);
    }
}
