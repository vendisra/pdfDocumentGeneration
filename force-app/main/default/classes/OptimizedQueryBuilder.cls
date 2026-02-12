/**
 * @description Builds optimized SOQL queries based on parsed template fields.
 * Only queries fields that are actually used in the template, significantly
 * reducing query size and improving performance.
 * 
 * Features:
 * - Supports deep parent relationship traversal (Account.Parent.Parent.Name)
 * - Supports nested child relationships (grandchildren)
 * - Validates field existence before including in query
 * - Includes fields from TemplateDataSource__c bind variables
 * 
 * SOQL Nested Subquery Limits:
 * - Salesforce allows nested subqueries up to a certain depth
 * - This implementation supports 2 levels: children and grandchildren
 * 
 * @author Document Generation Framework
 * @since 2024
 */
public with sharing class OptimizedQueryBuilder {
    
    // Maximum nesting depth for child relationships (children = 1, grandchildren = 2)
    private static final Integer MAX_NESTING_DEPTH = 2;
    
    // Pattern for extracting bind variables from filter conditions
    private static final Pattern BIND_VARIABLE_PATTERN = Pattern.compile(':(\\w+)');
    
    /**
     * @description Builds an optimized SOQL query for a template
     * @param objectApiName The main object API name
     * @param parsedFields The parsed field structure from template validation
     * @return String The SOQL query string
     */
    public static String buildQuery(String objectApiName, TemplateFieldParser.ParseResult parsedFields) {
        Set<String> selectFields = new Set<String>{'Id'};
        
        // Get valid fields for this object to filter out invalid ones
        Map<String, Schema.SObjectField> fieldMap = SchemaCache.getFieldMap(objectApiName);
        Set<String> validFieldNames = new Set<String>();
        for (String fieldName : fieldMap.keySet()) {
            validFieldNames.add(fieldName.toLowerCase());
        }
        
        // Add main object fields (only if they exist on the object)
        for (TemplateFieldParser.ParsedField field : parsedFields.mainObjectFields) {
            if (String.isNotBlank(field.fieldName)) {
                // Skip special GAS-side markers (PAGE_BREAK, IMAGE:*) - these are not Salesforce fields
                if (isSpecialMarker(field.fieldName)) {
                    continue;
                }
                // Validate field exists on object
                if (validFieldNames.contains(field.fieldName.toLowerCase())) {
                    selectFields.add(field.fieldName);
                } else {
                    System.debug(LoggingLevel.WARN, 'Skipping invalid field for ' + objectApiName + ': ' + field.fieldName);
                }
            }
        }
        
        // Add parent relationship fields (supports deep traversal like Account.Parent.Name)
        for (TemplateFieldParser.ParsedField field : parsedFields.parentRelationshipFields) {
            if (String.isNotBlank(field.relationshipPath)) {
                selectFields.add(field.relationshipPath);
            }
        }
        
        // Build main query SELECT clause
        String query = 'SELECT ' + String.join(new List<String>(selectFields), ', ');
        
        // Add child relationship subqueries with nested children support
        List<String> subqueries = new List<String>();
        for (TemplateFieldParser.ParsedField childRel : parsedFields.childRelationships) {
            String subquery = buildChildSubqueryWithNesting(objectApiName, childRel, 1);
            if (String.isNotBlank(subquery)) {
                subqueries.add(subquery);
            }
        }
        
        if (!subqueries.isEmpty()) {
            query += ', ' + String.join(subqueries, ', ');
        }
        
        // Add FROM and WHERE clauses
        query += ' FROM ' + String.escapeSingleQuotes(objectApiName) + 
                 ' WHERE Id = :recordId LIMIT 1';
        
        return query;
    }
    
    /**
     * @description Builds a child relationship subquery with support for nested children (grandchildren)
     * @param parentObjectName The parent object API name (e.g., Quote)
     * @param childRelationship The parsed child relationship with its fields
     * @param currentDepth Current nesting depth (1 = child, 2 = grandchild)
     * @return String The subquery string
     */
    private static String buildChildSubqueryWithNesting(
        String parentObjectName, 
        TemplateFieldParser.ParsedField childRelationship,
        Integer currentDepth
    ) {
        Set<String> childSelectFields = new Set<String>{'Id'};
        String relationshipName = childRelationship.fieldName;
        
        // Get child object name using the PARENT object and relationship name
        String childObjectName = TemplateFieldParser.getChildObjectName(parentObjectName, relationshipName);
        
        System.debug(LoggingLevel.INFO, 'Building subquery (depth ' + currentDepth + ') for relationship: ' + relationshipName + 
                     ' on parent: ' + parentObjectName + ' -> child object: ' + childObjectName);
        
        Map<String, Schema.SObjectField> childFieldMap = null;
        Set<String> validChildFieldNames = new Set<String>();
        
        if (String.isNotBlank(childObjectName)) {
            try {
                childFieldMap = SchemaCache.getFieldMap(childObjectName);
                for (String fieldName : childFieldMap.keySet()) {
                    validChildFieldNames.add(fieldName.toLowerCase());
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Could not get field map for child object: ' + childObjectName);
            }
        }
        
        // Add direct child fields and their relationships
        for (TemplateFieldParser.ParsedField childField : childRelationship.childFields) {
            // Skip special GAS-side markers (PAGE_BREAK, IMAGE:*) - these are not Salesforce fields
            if (String.isNotBlank(childField.fieldName) && isSpecialMarker(childField.fieldName)) {
                continue;
            }
            
            if (childField.fieldType == TemplateFieldParser.FieldType.MAIN_OBJECT) {
                // Validate field exists if we have the field map
                if (validChildFieldNames.isEmpty() || validChildFieldNames.contains(childField.fieldName.toLowerCase())) {
                    childSelectFields.add(childField.fieldName);
                } else {
                    System.debug(LoggingLevel.WARN, 'Skipping invalid child field for ' + childObjectName + ': ' + childField.fieldName);
                }
            } else if (childField.fieldType == TemplateFieldParser.FieldType.PARENT_RELATIONSHIP) {
                // Support deeper relationships within child (e.g., Product2.Family in QuoteLineItem)
                childSelectFields.add(childField.relationshipPath);
            } else if (childField.fieldType == TemplateFieldParser.FieldType.SYSTEM_VARIABLE ||
                       childField.fieldType == TemplateFieldParser.FieldType.DATA_SOURCE) {
                // Skip system variables and data source refs in subqueries
                continue;
            }
        }
        
        // Build nested subqueries for grandchildren (if within depth limit)
        List<String> nestedSubqueries = new List<String>();
        if (currentDepth < MAX_NESTING_DEPTH && 
            childRelationship.nestedChildren != null && 
            !childRelationship.nestedChildren.isEmpty() &&
            String.isNotBlank(childObjectName)) {
            
            for (TemplateFieldParser.ParsedField nestedChild : childRelationship.nestedChildren) {
                String nestedSubquery = buildChildSubqueryWithNesting(childObjectName, nestedChild, currentDepth + 1);
                if (String.isNotBlank(nestedSubquery)) {
                    nestedSubqueries.add(nestedSubquery);
                }
            }
        }
        
        // Log what fields we're including
        System.debug(LoggingLevel.INFO, 'Child subquery fields for ' + relationshipName + ': ' + childSelectFields);
        if (!nestedSubqueries.isEmpty()) {
            System.debug(LoggingLevel.INFO, 'Including ' + nestedSubqueries.size() + ' nested subqueries for grandchildren');
        }
        
        // Build the subquery
        String subquery = '(SELECT ' + String.join(new List<String>(childSelectFields), ', ');
        
        // Add nested subqueries if any
        if (!nestedSubqueries.isEmpty()) {
            subquery += ', ' + String.join(nestedSubqueries, ', ');
        }
        
        subquery += ' FROM ' + relationshipName + ' LIMIT 200)';
        
        return subquery;
    }
    
    /**
     * @description Legacy method for backward compatibility
     */
    private static String buildChildSubquery(String parentObjectName, TemplateFieldParser.ParsedField childRelationship) {
        return buildChildSubqueryWithNesting(parentObjectName, childRelationship, 1);
    }
    
    /**
     * @description Convenience method to build query from stored JSON
     * @param objectApiName The main object API name
     * @param parsedFieldsJSON The JSON from DocumentTemplate__c.ParsedFieldsJSON__c
     * @return String The SOQL query
     */
    public static String buildQueryFromJSON(String objectApiName, String parsedFieldsJSON) {
        if (String.isBlank(parsedFieldsJSON)) {
            throw new OptimizedQueryBuilderException('Parsed fields JSON is empty. Template must be validated first.');
        }
        
        TemplateFieldParser.ParseResult parsedFields = TemplateFieldParser.fromJSON(parsedFieldsJSON);
        return buildQuery(objectApiName, parsedFields);
    }
    
    /**
     * @description Builds query with bind variable fields from TemplateDataSource__c
     * This ensures fields used in data source filters (e.g., :AccountId, :Region__c)
     * are included in the main query so bind variables resolve correctly.
     * 
     * @param objectApiName The main object API name
     * @param parsedFieldsJSON The JSON from DocumentTemplate__c.ParsedFieldsJSON__c
     * @param templateId The DocumentTemplate__c record ID (to query data sources)
     * @return String The SOQL query including bind variable fields
     */
    public static String buildQueryFromJSONWithDataSources(String objectApiName, String parsedFieldsJSON, Id templateId) {
        if (String.isBlank(parsedFieldsJSON)) {
            throw new OptimizedQueryBuilderException('Parsed fields JSON is empty. Template must be validated first.');
        }
        
        TemplateFieldParser.ParseResult parsedFields = TemplateFieldParser.fromJSON(parsedFieldsJSON);
        
        // Get additional fields required for data source bind variables
        Set<String> bindVariableFields = getBindVariableFieldsFromDataSources(templateId);
        
        return buildQueryWithAdditionalFields(objectApiName, parsedFields, bindVariableFields);
    }
    
    /**
     * @description Builds query with additional fields beyond what's in the template
     * @param objectApiName The main object API name
     * @param parsedFields The parsed template fields
     * @param additionalFields Additional fields to include (e.g., bind variable fields)
     * @return String The SOQL query
     */
    public static String buildQueryWithAdditionalFields(
        String objectApiName, 
        TemplateFieldParser.ParseResult parsedFields,
        Set<String> additionalFields
    ) {
        Set<String> selectFields = new Set<String>{'Id'};
        
        // Get valid fields for this object to filter out invalid ones
        Map<String, Schema.SObjectField> fieldMap = SchemaCache.getFieldMap(objectApiName);
        Set<String> validFieldNames = new Set<String>();
        for (String fieldName : fieldMap.keySet()) {
            validFieldNames.add(fieldName.toLowerCase());
        }
        
        // Add main object fields (only if they exist on the object)
        for (TemplateFieldParser.ParsedField field : parsedFields.mainObjectFields) {
            if (String.isNotBlank(field.fieldName)) {
                // Skip special GAS-side markers (PAGE_BREAK, IMAGE:*) - these are not Salesforce fields
                if (isSpecialMarker(field.fieldName)) {
                    continue;
                }
                // Validate field exists on object
                if (validFieldNames.contains(field.fieldName.toLowerCase())) {
                    selectFields.add(field.fieldName);
                } else {
                    System.debug(LoggingLevel.WARN, 'Skipping invalid field for ' + objectApiName + ': ' + field.fieldName);
                }
            }
        }
        
        // Add parent relationship fields (supports deep traversal like Account.Parent.Name)
        for (TemplateFieldParser.ParsedField field : parsedFields.parentRelationshipFields) {
            if (String.isNotBlank(field.relationshipPath)) {
                selectFields.add(field.relationshipPath);
            }
        }
        
        // Add additional fields (bind variable fields from data sources)
        if (additionalFields != null) {
            for (String additionalField : additionalFields) {
                if (String.isNotBlank(additionalField)) {
                    // Handle simple fields and relationship paths
                    if (additionalField.contains('.')) {
                        // Relationship path - add as-is
                        selectFields.add(additionalField);
                        System.debug(LoggingLevel.INFO, 'Added bind variable relationship field: ' + additionalField);
                    } else if (validFieldNames.contains(additionalField.toLowerCase())) {
                        selectFields.add(additionalField);
                        System.debug(LoggingLevel.INFO, 'Added bind variable field: ' + additionalField);
                    } else {
                        System.debug(LoggingLevel.WARN, 'Skipping invalid bind variable field for ' + objectApiName + ': ' + additionalField);
                    }
                }
            }
        }
        
        // Build main query SELECT clause
        String query = 'SELECT ' + String.join(new List<String>(selectFields), ', ');
        
        // Add child relationship subqueries with nested children support
        List<String> subqueries = new List<String>();
        for (TemplateFieldParser.ParsedField childRel : parsedFields.childRelationships) {
            String subquery = buildChildSubqueryWithNesting(objectApiName, childRel, 1);
            if (String.isNotBlank(subquery)) {
                subqueries.add(subquery);
            }
        }
        
        if (!subqueries.isEmpty()) {
            query += ', ' + String.join(subqueries, ', ');
        }
        
        // Add FROM and WHERE clauses
        query += ' FROM ' + String.escapeSingleQuotes(objectApiName) + 
                 ' WHERE Id = :recordId LIMIT 1';
        
        return query;
    }
    
    /**
     * @description Extracts field names used as bind variables in TemplateDataSource__c filter conditions
     * For example, if a filter is "AccountId = :AccountId AND Region__c = :Region__c",
     * this returns {AccountId, Region__c}
     * 
     * @param templateId The DocumentTemplate__c record ID
     * @return Set<String> Field names that need to be included in the main query
     */
    public static Set<String> getBindVariableFieldsFromDataSources(Id templateId) {
        Set<String> bindVariableFields = new Set<String>();
        
        if (templateId == null) {
            return bindVariableFields;
        }
        
        // Query active data sources for this template
        List<TemplateDataSource__c> dataSources = [
            SELECT FilterCondition__c
            FROM TemplateDataSource__c
            WHERE DocumentTemplate__c = :templateId
            AND IsActive__c = true
            WITH USER_MODE
        ];
        
        // Extract bind variable field names from each filter condition
        for (TemplateDataSource__c ds : dataSources) {
            if (String.isNotBlank(ds.FilterCondition__c)) {
                Set<String> fields = extractBindVariableFields(ds.FilterCondition__c);
                bindVariableFields.addAll(fields);
            }
        }
        
        if (!bindVariableFields.isEmpty()) {
            System.debug(LoggingLevel.INFO, 'Bind variable fields from data sources: ' + bindVariableFields);
        }
        
        return bindVariableFields;
    }
    
    /**
     * @description Extracts field names from bind variable references in a filter condition
     * Supports simple fields (:AccountId) and relationship paths (:Account.BillingState)
     * 
     * @param filterCondition The filter condition string (e.g., "AccountId = :AccountId")
     * @return Set<String> Field names or relationship paths
     */
    private static Set<String> extractBindVariableFields(String filterCondition) {
        Set<String> fields = new Set<String>();
        
        if (String.isBlank(filterCondition)) {
            return fields;
        }
        
        Matcher m = BIND_VARIABLE_PATTERN.matcher(filterCondition);
        
        while (m.find()) {
            String fieldPath = m.group(1);
            if (String.isNotBlank(fieldPath)) {
                fields.add(fieldPath);
            }
        }
        
        return fields;
    }
    
    /**
     * @description Gets the set of SOQL field paths for a template
     * Useful for manual query building or validation
     */
    public static Set<String> getRequiredFields(TemplateFieldParser.ParseResult parsedFields) {
        Set<String> fields = new Set<String>{'Id'};
        
        for (TemplateFieldParser.ParsedField field : parsedFields.mainObjectFields) {
            fields.add(field.fieldName);
        }
        
        for (TemplateFieldParser.ParsedField field : parsedFields.parentRelationshipFields) {
            fields.add(field.relationshipPath);
        }
        
        return fields;
    }
    
    /**
     * @description Gets the set of child relationship names for a template
     */
    public static Set<String> getRequiredChildRelationships(TemplateFieldParser.ParseResult parsedFields) {
        Set<String> relationships = new Set<String>();
        
        for (TemplateFieldParser.ParsedField childRel : parsedFields.childRelationships) {
            relationships.add(childRel.fieldName);
        }
        
        return relationships;
    }
    
    /**
     * @description Checks if a field name is a special GAS-side marker
     * These markers are processed by the GAS middleware, not by Salesforce
     * @param fieldName The field name to check
     * @return Boolean True if this is a special marker that should be skipped
     */
    private static Boolean isSpecialMarker(String fieldName) {
        if (String.isBlank(fieldName)) {
            return false;
        }
        
        String upperName = fieldName.toUpperCase();
        
        // PAGE_BREAK - GAS-side page break marker
        if (upperName == 'PAGE_BREAK') {
            return true;
        }
        
        // IMAGE markers - {{IMAGE:FieldName}} or {{IMAGE:FieldName:widthxheight}}
        // The stored field name might just be "IMAGE" after parsing
        if (upperName == 'IMAGE' || upperName.startsWith('IMAGE:')) {
            return true;
        }
        
        return false;
    }
    
    /**
     * @description Custom exception for query builder errors
     */
    public class OptimizedQueryBuilderException extends Exception {}
}
