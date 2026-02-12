/**
 * @description Service for fetching Salesforce data with FLS enforcement.
 * Uses USER_MODE for automatic FLS/CRUD enforcement at query time.
 * 
 * Design Decision: We rely on Database.queryWithBinds with AccessLevel.USER_MODE
 * which automatically enforces FLS. If a field is inaccessible, it's simply not
 * returned (no exception). This is more efficient than manual isAccessible() checks.
 * 
 * Fail-Fast Policy: If a template is not validated or fields cannot be parsed,
 * the process will throw an exception rather than attempting a blind "select all"
 * query. This prevents massive, inefficient queries and ensures data integrity.
 * 
 * @author Document Generation Framework
 * @since 2024
 */
public with sharing class DataProviderService {
    
    /**
     * @description Exception for data access errors
     */
    public class DataAccessException extends Exception {}
    
    // Maximum fields per query to avoid query length limits
    private static final Integer MAX_FIELDS_PER_QUERY = 200;
    private static final Integer MAX_CHILD_FIELDS = 50;
    private static final Integer MAX_CHILD_RELATIONSHIPS = 5;
    
    // Cache for name fields by object (populated via FieldDefinition query)
    private static Map<String, String> nameFieldCache = new Map<String, String>();
    
    // Field types that cannot be selected in queries (especially subqueries)
    private static final Set<Schema.DisplayType> EXCLUDED_FIELD_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.BASE64,           // Binary/Blob fields
        Schema.DisplayType.ADDRESS,          // Compound address
        Schema.DisplayType.LOCATION,         // Geolocation compound
        Schema.DisplayType.ENCRYPTEDSTRING   // Encrypted fields in subqueries
    };
    
    /**
     * @description Fetches record data using optimized query based on template fields.
     * IMPORTANT: This method requires a validated template with parsed fields.
     * It will NOT fall back to a "select all" query - if the template is invalid,
     * an exception is thrown to fail fast.
     * 
     * NOTE: This overload does NOT include bind variable fields from TemplateDataSource__c.
     * Use the overload with templateId parameter if you have data sources with bind variables.
     * 
     * @param recordId The record ID to query
     * @param objectApiName The object API name
     * @param parsedFieldsJSON The JSON from DocumentTemplate__c.ParsedFieldsJSON__c
     * @return SObject The queried record with required fields
     * @throws DataAccessException if template is not validated or query fails
     */
    public static SObject fetchRecordDataOptimized(Id recordId, String objectApiName, String parsedFieldsJSON) {
        return fetchRecordDataOptimized(recordId, objectApiName, parsedFieldsJSON, null);
    }
    
    /**
     * @description Fetches record data using optimized query based on template fields,
     * including fields required for TemplateDataSource__c bind variables.
     * 
     * This method ensures that fields used in data source filter conditions
     * (e.g., :AccountId, :Region__c) are included in the query so bind variables resolve.
     * 
     * @param recordId The record ID to query
     * @param objectApiName The object API name
     * @param parsedFieldsJSON The JSON from DocumentTemplate__c.ParsedFieldsJSON__c
     * @param templateId The DocumentTemplate__c record ID (for querying data source bind variables)
     * @return SObject The queried record with required fields
     * @throws DataAccessException if template is not validated or query fails
     */
    public static SObject fetchRecordDataOptimized(Id recordId, String objectApiName, String parsedFieldsJSON, Id templateId) {
        // Validate object exists and is accessible
        if (!SchemaCache.isObjectAccessible(objectApiName)) {
            throw new DataAccessException('Object not accessible: ' + objectApiName);
        }
        
        // FAIL FAST: Require parsed fields JSON - no fallback to "select all"
        if (String.isBlank(parsedFieldsJSON)) {
            throw new DataAccessException(
                'Template must be validated before document generation. ' +
                'ParsedFieldsJSON is empty for object: ' + objectApiName + '. ' +
                'Please run template validation first.'
            );
        }
        
        // Build optimized query from parsed fields
        String query;
        try {
            if (templateId != null) {
                // Include bind variable fields from data sources
                query = OptimizedQueryBuilder.buildQueryFromJSONWithDataSources(objectApiName, parsedFieldsJSON, templateId);
            } else {
                query = OptimizedQueryBuilder.buildQueryFromJSON(objectApiName, parsedFieldsJSON);
            }
        } catch (Exception e) {
            // FAIL FAST: Don't fall back to a blind query
            throw new DataAccessException(
                'Failed to build query from template fields: ' + e.getMessage() + '. ' +
                'Please re-validate the template.'
            );
        }
        
        System.debug(LoggingLevel.INFO, 'Optimized query: ' + query);
        
        // Execute with USER_MODE for automatic FLS enforcement
        Map<String, Object> bindVars = new Map<String, Object>{
            'recordId' => recordId
        };
        
        List<SObject> records = Database.queryWithBinds(
            query, 
            bindVars, 
            AccessLevel.USER_MODE
        );
        
        if (records.isEmpty()) {
            throw new DataAccessException('Record not found or not accessible: ' + recordId);
        }
        
        return records[0];
    }
    
    /**
     * @description Gets the name field for an object using FieldDefinition
     * This is the single source of truth for name fields - no hardcoding.
     * Caches results to avoid repeated queries.
     * @param objectApiName The API name of the object
     * @return The name field API name, or null if none found
     */
    public static String getNameFieldForObject(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return null;
        }
        
        // Check cache first
        if (nameFieldCache.containsKey(objectApiName)) {
            return nameFieldCache.get(objectApiName);
        }
        
        // Query FieldDefinition for the name field
        String nameField = queryNameFieldFromDefinition(objectApiName);
        nameFieldCache.put(objectApiName, nameField);
        return nameField;
    }
    
    /**
     * @description Queries FieldDefinition to find the name field
     */
    private static String queryNameFieldFromDefinition(String objectApiName) {
        try {
            List<FieldDefinition> fieldDefs = [
                SELECT QualifiedApiName
                FROM FieldDefinition
                WHERE EntityDefinition.QualifiedApiName = :objectApiName
                AND IsNameField = true
                LIMIT 1
            ];
            
            if (!fieldDefs.isEmpty()) {
                return fieldDefs[0].QualifiedApiName;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Could not query FieldDefinition for ' + objectApiName + ': ' + e.getMessage());
        }
        
        return null;
    }
    
    /**
     * @description Pre-loads name fields for multiple objects in a single query
     * Call this before processing multiple records to optimize SOQL usage
     * @param objectApiNames Set of object API names to preload
     */
    public static void preloadNameFields(Set<String> objectApiNames) {
        if (objectApiNames == null || objectApiNames.isEmpty()) {
            return;
        }
        
        // Filter out already cached objects
        Set<String> objectsToQuery = new Set<String>();
        for (String objName : objectApiNames) {
            if (!nameFieldCache.containsKey(objName)) {
                objectsToQuery.add(objName);
            }
        }
        
        if (objectsToQuery.isEmpty()) {
            return;
        }
        
        try {
            List<FieldDefinition> fieldDefs = [
                SELECT EntityDefinition.QualifiedApiName, QualifiedApiName
                FROM FieldDefinition
                WHERE EntityDefinition.QualifiedApiName IN :objectsToQuery
                AND IsNameField = true
            ];
            
            for (FieldDefinition fd : fieldDefs) {
                nameFieldCache.put(fd.EntityDefinition.QualifiedApiName, fd.QualifiedApiName);
            }
            
            // Mark objects without name fields as null to avoid re-querying
            for (String objName : objectsToQuery) {
                if (!nameFieldCache.containsKey(objName)) {
                    nameFieldCache.put(objName, null);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Could not preload name fields: ' + e.getMessage());
        }
    }
    
    // =========================================================================
    // DATA SOURCE QUERY SUPPORT (replaces cross-object queries)
    // =========================================================================
    
    /**
     * @description Fetches data from TemplateDataSource__c records for a template.
     * This is the secure replacement for the old {{@Alias:Object[Filter]}} syntax.
     * 
     * @param templateId The DocumentTemplate__c record ID
     * @param mainRecordData Map of main record field values (for bind variables)
     * @return Map<String, Object> Map of alias -> data suitable for GAS payload
     */
    public static Map<String, Object> fetchDataSourceData(
        Id templateId,
        Map<String, Object> mainRecordData
    ) {
        if (templateId == null) {
            return new Map<String, Object>();
        }
        
        System.debug(LoggingLevel.INFO, 'Fetching data source data for template: ' + templateId);
        
        // Execute all data source queries
        Map<String, CrossObjectQueryBuilder.CrossObjectResult> results = 
            CrossObjectQueryBuilder.executeDataSourceQueries(templateId, mainRecordData);
        
        // Convert results to map format for GAS payload
        Map<String, Object> dataSourceData = CrossObjectQueryBuilder.convertResultsToMap(results);
        
        // Log any errors
        for (String alias : results.keySet()) {
            CrossObjectQueryBuilder.CrossObjectResult result = results.get(alias);
            if (!result.success) {
                System.debug(LoggingLevel.WARN, 'Data source query failed for alias ' + alias + ': ' + result.errorMessage);
            } else {
                System.debug(LoggingLevel.INFO, 'Data source ' + alias + ': ' + result.records.size() + ' records');
            }
        }
        
        return dataSourceData;
    }
    
    /**
     * @description Fetches all data needed for document generation including data sources.
     * This is a convenience method that combines main record and data source fetching.
     * 
     * @param recordId The main record ID
     * @param objectApiName The main object API name
     * @param templateId The DocumentTemplate__c record ID (for data sources)
     * @param parsedFieldsJSON The JSON from DocumentTemplate__c.ParsedFieldsJSON__c
     * @return DataFetchResult Contains main record and data source data
     */
    public static DataFetchResult fetchAllData(
        Id recordId, 
        String objectApiName, 
        Id templateId,
        String parsedFieldsJSON
    ) {
        DataFetchResult result = new DataFetchResult();
        
        // Fetch main record data (will fail fast if template not validated)
        result.mainRecord = fetchRecordDataOptimized(recordId, objectApiName, parsedFieldsJSON);
        
        // Build main record data map for data source query bind variables
        Map<String, Object> mainRecordDataMap = buildRecordDataMap(result.mainRecord);
        
        // Fetch data source data if template has any configured
        if (templateId != null) {
            result.dataSourceData = fetchDataSourceData(templateId, mainRecordDataMap);
        }
        
        return result;
    }
    
    /**
     * @description Builds a map of field values from an SObject record
     * Used for bind variable resolution in data source queries
     */
    public static Map<String, Object> buildRecordDataMap(SObject record) {
        Map<String, Object> dataMap = new Map<String, Object>();
        
        if (record == null) {
            return dataMap;
        }
        
        Map<String, Object> populatedFields = record.getPopulatedFieldsAsMap();
        
        for (String fieldName : populatedFields.keySet()) {
            Object value = populatedFields.get(fieldName);
            
            // Skip child relationships
            if (value instanceof List<Object>) {
                continue;
            }
            
            // Handle related objects (parent lookups) - create nested map
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
                    dataMap.put(fieldName, nestedMap);
                }
            } else {
                dataMap.put(fieldName, value);
            }
        }
        
        return dataMap;
    }
    
    /**
     * @description Result class containing all fetched data for document generation
     */
    public class DataFetchResult {
        public SObject mainRecord { get; set; }
        public Map<String, Object> dataSourceData { get; set; }
        
        public DataFetchResult() {
            this.dataSourceData = new Map<String, Object>();
        }
    }
}
