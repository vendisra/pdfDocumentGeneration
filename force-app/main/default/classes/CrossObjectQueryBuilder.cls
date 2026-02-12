/**
 * @description Builds and executes SOQL queries for cross-object data sources.
 * Uses TemplateDataSource__c records to define queries in a secure, admin-controlled manner.
 * 
 * Security:
 * - Filter conditions use bind variables (:FieldName) instead of string concatenation
 * - All queries use WITH USER_MODE for automatic FLS enforcement
 * - Object and field accessibility is validated before query execution
 * - No dynamic SOQL from template text - all queries defined in Salesforce records
 * 
 * @author Document Generation Framework
 * @since 2024
 */
public with sharing class CrossObjectQueryBuilder {
    
    // Maximum records per cross-object query
    private static final Integer MAX_RECORDS_PER_QUERY = 200;
    
    // Maximum data sources per template
    private static final Integer MAX_DATA_SOURCES_PER_TEMPLATE = 10;
    
    /**
     * @description Result of a cross-object query
     */
    public class CrossObjectResult {
        public String alias { get; set; }
        public String objectName { get; set; }
        public List<SObject> records { get; set; }
        public Boolean success { get; set; }
        public String errorMessage { get; set; }
        
        public CrossObjectResult() {
            this.records = new List<SObject>();
            this.success = true;
        }
    }
    
    /**
     * @description Executes all active data source queries for a template
     * @param templateId The DocumentTemplate__c record ID
     * @param mainRecordData Map of main record field values (for bind variables)
     * @return Map<String, CrossObjectResult> Results keyed by alias
     */
    public static Map<String, CrossObjectResult> executeDataSourceQueries(
        Id templateId,
        Map<String, Object> mainRecordData
    ) {
        Map<String, CrossObjectResult> results = new Map<String, CrossObjectResult>();
        
        if (templateId == null) {
            return results;
        }
        
        // Query active data sources for this template
        List<TemplateDataSource__c> dataSources = [
            SELECT Id, Alias__c, ObjectApiName__c, FilterCondition__c, 
                   FieldList__c, OrderBy__c, RecordLimit__c
            FROM TemplateDataSource__c
            WHERE DocumentTemplate__c = :templateId
            AND IsActive__c = true
            WITH USER_MODE
            ORDER BY SortOrder__c ASC NULLS LAST
            LIMIT :MAX_DATA_SOURCES_PER_TEMPLATE
        ];
        
        if (dataSources.isEmpty()) {
            return results;
        }
        
        for (TemplateDataSource__c dataSource : dataSources) {
            CrossObjectResult result = executeDataSourceQuery(dataSource, mainRecordData);
            results.put(dataSource.Alias__c, result);
        }
        
        return results;
    }
    
    /**
     * @description Executes a single data source query
     * @param dataSource The TemplateDataSource__c record
     * @param mainRecordData Map of main record field values (for bind variables)
     * @return CrossObjectResult The query result
     */
    public static CrossObjectResult executeDataSourceQuery(
        TemplateDataSource__c dataSource,
        Map<String, Object> mainRecordData
    ) {
        CrossObjectResult result = new CrossObjectResult();
        result.alias = dataSource.Alias__c;
        result.objectName = dataSource.ObjectApiName__c;
        
        try {
            // Validate object accessibility
            if (!SchemaCache.isObjectAccessible(dataSource.ObjectApiName__c)) {
                result.success = false;
                result.errorMessage = 'Object not accessible: ' + dataSource.ObjectApiName__c;
                return result;
            }
            
            // Build and execute query with bind variables
            QueryComponents components = buildQueryComponents(dataSource, mainRecordData);
            
            System.debug(LoggingLevel.INFO, 'Data source query for ' + dataSource.Alias__c + ': ' + components.queryString);
            
            // Execute with USER_MODE for FLS enforcement
            result.records = Database.queryWithBinds(
                components.queryString, 
                components.bindVariables, 
                AccessLevel.USER_MODE
            );
            
            System.debug(LoggingLevel.INFO, 'Data source query returned ' + result.records.size() + ' records');
            
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = 'Query failed: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'Data source query failed for ' + dataSource.Alias__c + ': ' + e.getMessage());
        }
        
        return result;
    }
    
    /**
     * @description Query components including string and bind variables
     */
    private class QueryComponents {
        public String queryString;
        public Map<String, Object> bindVariables;
        
        public QueryComponents() {
            this.bindVariables = new Map<String, Object>();
        }
    }
    
    /**
     * @description Builds query components with proper bind variable handling
     * @param dataSource The data source configuration
     * @param mainRecordData Map of main record field values
     * @return QueryComponents The query string and bind variables
     */
    private static QueryComponents buildQueryComponents(
        TemplateDataSource__c dataSource,
        Map<String, Object> mainRecordData
    ) {
        QueryComponents components = new QueryComponents();
        
        // Get fields to query
        Set<String> fields = getFieldsToQuery(dataSource);
        
        // Build SELECT clause
        String selectClause = 'SELECT ' + String.join(new List<String>(fields), ', ');
        
        // Build FROM clause
        String fromClause = ' FROM ' + String.escapeSingleQuotes(dataSource.ObjectApiName__c);
        
        // Build WHERE clause with bind variables
        String whereClause = buildWhereClause(dataSource.FilterCondition__c, mainRecordData, components.bindVariables);
        
        // Build ORDER BY clause
        String orderByClause = '';
        if (String.isNotBlank(dataSource.OrderBy__c)) {
            // Sanitize ORDER BY to only allow field names and ASC/DESC
            String sanitizedOrderBy = sanitizeOrderBy(dataSource.OrderBy__c);
            if (String.isNotBlank(sanitizedOrderBy)) {
                orderByClause = ' ORDER BY ' + sanitizedOrderBy;
            }
        }
        
        // Determine limit
        Integer recordLimit = dataSource.RecordLimit__c != null 
            ? Math.min(Integer.valueOf(dataSource.RecordLimit__c), MAX_RECORDS_PER_QUERY)
            : MAX_RECORDS_PER_QUERY;
        
        // Combine query
        components.queryString = selectClause + fromClause + whereClause + orderByClause + 
                                ' LIMIT ' + recordLimit;
        
        return components;
    }
    
    /**
     * @description Gets the fields to include in the query
     * @param dataSource The data source configuration
     * @return Set<String> Set of field API names
     */
    private static Set<String> getFieldsToQuery(TemplateDataSource__c dataSource) {
        Set<String> fields = new Set<String>{'Id'};
        
        // If explicit field list provided, use it
        if (String.isNotBlank(dataSource.FieldList__c)) {
            for (String field : dataSource.FieldList__c.split(',')) {
                String trimmedField = field.trim();
                if (String.isNotBlank(trimmedField)) {
                    fields.add(trimmedField);
                }
            }
            return fields;
        }
        
        // Otherwise, query common fields (name field detection)
        try {
            String nameField = DataProviderService.getNameFieldForObject(dataSource.ObjectApiName__c);
            if (String.isNotBlank(nameField)) {
                fields.add(nameField);
            }
            
            // Add some default useful fields if they exist
            Map<String, Schema.SObjectField> fieldMap = SchemaCache.getFieldMap(dataSource.ObjectApiName__c);
            Set<String> commonFields = new Set<String>{
                'CreatedDate', 'LastModifiedDate', 'OwnerId'
            };
            
            for (String commonField : commonFields) {
                if (fieldMap.containsKey(commonField.toLowerCase())) {
                    fields.add(commonField);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Could not get default fields for ' + dataSource.ObjectApiName__c);
        }
        
        return fields;
    }
    
    /**
     * @description Builds the WHERE clause with bind variables
     * Converts :FieldName placeholders to proper bind variables
     * @param filterCondition The filter condition with :FieldName placeholders
     * @param mainRecordData Map of main record field values
     * @param bindVariables Map to populate with bind variable values
     * @return String The WHERE clause (including WHERE keyword)
     */
    private static String buildWhereClause(
        String filterCondition, 
        Map<String, Object> mainRecordData,
        Map<String, Object> bindVariables
    ) {
        if (String.isBlank(filterCondition)) {
            return '';
        }
        
        String processedFilter = filterCondition;
        
        // Find all :FieldName bind variable references
        Pattern bindPattern = Pattern.compile(':(\\w+(?:\\.\\w+)*)');
        Matcher m = bindPattern.matcher(filterCondition);
        
        while (m.find()) {
            String fieldPath = m.group(1);
            Object value = resolveFieldValue(fieldPath, mainRecordData);
            
            // Add to bind variables map
            // Convert dots to underscores for bind variable names (SOQL requirement)
            String bindVarName = fieldPath.replace('.', '_');
            bindVariables.put(bindVarName, value);
            
            // Replace :Field.Path with :Field_Path in the query
            if (fieldPath.contains('.')) {
                processedFilter = processedFilter.replace(':' + fieldPath, ':' + bindVarName);
            }
        }
        
        return ' WHERE ' + processedFilter;
    }
    
    /**
     * @description Resolves a field value from the main record data
     * Supports nested paths like Account.BillingState
     * @param fieldPath The field path (e.g., "Id" or "Account.BillingState")
     * @param mainRecordData Map of main record field values
     * @return Object The resolved value
     */
    private static Object resolveFieldValue(String fieldPath, Map<String, Object> mainRecordData) {
        if (mainRecordData == null || String.isBlank(fieldPath)) {
            return null;
        }
        
        String[] parts = fieldPath.split('\\.');
        Object current = mainRecordData;
        
        for (String part : parts) {
            if (current == null) {
                return null;
            }
            
            if (current instanceof Map<String, Object>) {
                current = ((Map<String, Object>) current).get(part);
            } else {
                return null;
            }
        }
        
        return current;
    }
    
    /**
     * @description Sanitizes ORDER BY clause to prevent injection
     * Only allows field names, dots, commas, and ASC/DESC
     * @param orderBy The ORDER BY clause to sanitize
     * @return String The sanitized ORDER BY clause or empty string if invalid
     */
    private static String sanitizeOrderBy(String orderBy) {
        if (String.isBlank(orderBy)) {
            return '';
        }
        
        // Only allow alphanumeric, underscores, dots, commas, spaces, and ASC/DESC
        String sanitized = orderBy.replaceAll('[^a-zA-Z0-9_., ]', '');
        
        // Validate each part
        List<String> validParts = new List<String>();
        for (String part : sanitized.split(',')) {
            String trimmed = part.trim();
            // Pattern: FieldName (optional .SubField) (optional ASC/DESC)
            if (Pattern.matches('^[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z][a-zA-Z0-9_]*)?(\\s+(ASC|DESC))?$', trimmed)) {
                validParts.add(trimmed);
            }
        }
        
        return String.join(validParts, ', ');
    }
    
    /**
     * @description Validates a data source configuration
     * @param dataSource The data source to validate
     * @return List<String> List of validation errors (empty if valid)
     */
    public static List<String> validateDataSource(TemplateDataSource__c dataSource) {
        List<String> errors = new List<String>();
        
        if (dataSource == null) {
            errors.add('Data source is null');
            return errors;
        }
        
        // Validate alias
        if (String.isBlank(dataSource.Alias__c)) {
            errors.add('Alias is required');
        } else if (!Pattern.matches('^[a-zA-Z][a-zA-Z0-9_]*$', dataSource.Alias__c)) {
            errors.add('Invalid alias format: ' + dataSource.Alias__c + '. Must start with a letter and contain only letters, numbers, and underscores.');
        }
        
        // Validate object name
        if (String.isBlank(dataSource.ObjectApiName__c)) {
            errors.add('Object API Name is required');
        } else {
            try {
                if (!SchemaCache.isObjectAccessible(dataSource.ObjectApiName__c)) {
                    errors.add('Object not accessible: ' + dataSource.ObjectApiName__c);
                }
            } catch (Exception e) {
                errors.add('Invalid object: ' + dataSource.ObjectApiName__c);
            }
        }
        
        // Validate filter condition syntax
        if (String.isNotBlank(dataSource.FilterCondition__c)) {
            // Check for balanced quotes
            Integer singleQuotes = dataSource.FilterCondition__c.countMatches('\'');
            if (Math.mod(singleQuotes, 2) != 0) {
                errors.add('Unbalanced quotes in filter condition');
            }
            
            // Check for balanced parentheses
            Integer openParens = dataSource.FilterCondition__c.countMatches('(');
            Integer closeParens = dataSource.FilterCondition__c.countMatches(')');
            if (openParens != closeParens) {
                errors.add('Unbalanced parentheses in filter condition');
            }
            
            // Warn about potential issues (but don't error)
            if (dataSource.FilterCondition__c.contains('--') || dataSource.FilterCondition__c.contains('/*')) {
                errors.add('Filter condition contains comment-like patterns which are not allowed');
            }
        }
        
        // Validate field list if provided
        if (String.isNotBlank(dataSource.FieldList__c)) {
            Map<String, Schema.SObjectField> fieldMap = SchemaCache.getFieldMap(dataSource.ObjectApiName__c);
            for (String field : dataSource.FieldList__c.split(',')) {
                String trimmedField = field.trim();
                if (String.isBlank(trimmedField)) continue;
                
                // For simple fields, validate existence
                if (!trimmedField.contains('.')) {
                    if (!fieldMap.containsKey(trimmedField.toLowerCase()) && trimmedField.toLowerCase() != 'id') {
                        errors.add('Field not found on ' + dataSource.ObjectApiName__c + ': ' + trimmedField);
                    }
                }
                // Relationship fields will be validated at runtime
            }
        }
        
        // Validate record limit
        if (dataSource.RecordLimit__c != null && dataSource.RecordLimit__c > MAX_RECORDS_PER_QUERY) {
            errors.add('Record limit exceeds maximum of ' + MAX_RECORDS_PER_QUERY);
        }
        
        return errors;
    }
    
    /**
     * @description Converts cross-object query results to a map structure for GAS
     * @param results The query results
     * @return Map<String, Object> Map structure suitable for GAS payload
     */
    public static Map<String, Object> convertResultsToMap(Map<String, CrossObjectResult> results) {
        Map<String, Object> dataMap = new Map<String, Object>();
        
        for (String alias : results.keySet()) {
            CrossObjectResult result = results.get(alias);
            
            if (!result.success || result.records.isEmpty()) {
                // Add empty list for failed or empty queries (for table processing)
                dataMap.put(alias, new List<Map<String, Object>>());
                continue;
            }
            
            // Always return as list for consistent table/repeater processing in GAS
            List<Map<String, Object>> recordList = new List<Map<String, Object>>();
            for (SObject record : result.records) {
                recordList.add(convertRecordToMap(record));
            }
            dataMap.put(alias, recordList);
        }
        
        return dataMap;
    }
    
    /**
     * @description Converts an SObject record to a map
     * @param record The SObject record
     * @return Map<String, Object> The field map
     */
    private static Map<String, Object> convertRecordToMap(SObject record) {
        Map<String, Object> fieldMap = new Map<String, Object>();
        Map<String, Object> populatedFields = record.getPopulatedFieldsAsMap();
        
        for (String fieldName : populatedFields.keySet()) {
            Object value = populatedFields.get(fieldName);
            
            // Skip complex types
            if (value instanceof List<Object>) {
                continue;
            }
            
            // Handle related objects (nested)
            if (value instanceof SObject) {
                SObject relatedRecord = (SObject) value;
                Map<String, Object> relatedFields = relatedRecord.getPopulatedFieldsAsMap();
                Map<String, Object> nestedMap = new Map<String, Object>();
                
                for (String relField : relatedFields.keySet()) {
                    Object relValue = relatedFields.get(relField);
                    if (!(relValue instanceof SObject) && !(relValue instanceof List<Object>)) {
                        nestedMap.put(relField, relValue);
                    }
                }
                
                if (!nestedMap.isEmpty()) {
                    fieldMap.put(fieldName, nestedMap);
                }
            } else {
                fieldMap.put(fieldName, value);
            }
        }
        
        return fieldMap;
    }
    
    /**
     * @description Custom exception for cross-object query errors
     */
    public class CrossObjectQueryException extends Exception {}
}
