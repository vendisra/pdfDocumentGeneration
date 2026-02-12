/**
 * @description Caching utility for Salesforce schema metadata.
 * Reduces expensive Schema.getGlobalDescribe() calls by caching results.
 * 
 * @author Document Generation Framework
 * @since 2024
 */
public with sharing class SchemaCache {
    
    // Cache for SObjectType lookups
    private static Map<String, Schema.SObjectType> sObjectTypeCache = new Map<String, Schema.SObjectType>();
    
    // Cache for SObjectDescribe results
    private static Map<String, Schema.DescribeSObjectResult> describeCache = new Map<String, Schema.DescribeSObjectResult>();
    
    // Cache for field maps
    private static Map<String, Map<String, Schema.SObjectField>> fieldMapCache = new Map<String, Map<String, Schema.SObjectField>>();
    
    // Cache for child relationships
    private static Map<String, List<Schema.ChildRelationship>> childRelCache = new Map<String, List<Schema.ChildRelationship>>();
    
    // Cache for non-existent objects (negative cache)
    private static Set<String> nonExistentObjects = new Set<String>();
    
    /**
     * @description Gets the SObjectType for an object API name
     * @param objectApiName The API name of the object
     * @return Schema.SObjectType The SObject type or null if not found
     */
    public static Schema.SObjectType getSObjectType(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return null;
        }
        
        String cacheKey = objectApiName.toLowerCase();
        
        // Check negative cache first
        if (nonExistentObjects.contains(cacheKey)) {
            return null;
        }
        
        // Check positive cache
        if (sObjectTypeCache.containsKey(cacheKey)) {
            return sObjectTypeCache.get(cacheKey);
        }
        
        // Look up in global describe
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
        
        if (sObjectType == null) {
            // Add to negative cache
            nonExistentObjects.add(cacheKey);
        } else {
            // Add to positive cache
            sObjectTypeCache.put(cacheKey, sObjectType);
        }
        
        return sObjectType;
    }
    
    /**
     * @description Gets the describe result for an object
     * @param objectApiName The API name of the object
     * @return Schema.DescribeSObjectResult The describe result or null
     */
    public static Schema.DescribeSObjectResult getDescribe(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return null;
        }
        
        String cacheKey = objectApiName.toLowerCase();
        
        // Check cache
        if (describeCache.containsKey(cacheKey)) {
            return describeCache.get(cacheKey);
        }
        
        // Get SObjectType
        Schema.SObjectType sObjectType = getSObjectType(objectApiName);
        if (sObjectType == null) {
            return null;
        }
        
        // Get describe result
        Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
        describeCache.put(cacheKey, describeResult);
        
        return describeResult;
    }
    
    /**
     * @description Gets the field map for an object
     * @param objectApiName The API name of the object
     * @return Map<String, Schema.SObjectField> The field map or empty map
     */
    public static Map<String, Schema.SObjectField> getFieldMap(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return new Map<String, Schema.SObjectField>();
        }
        
        String cacheKey = objectApiName.toLowerCase();
        
        // Check cache
        if (fieldMapCache.containsKey(cacheKey)) {
            return fieldMapCache.get(cacheKey);
        }
        
        // Get describe result
        Schema.DescribeSObjectResult describeResult = getDescribe(objectApiName);
        if (describeResult == null) {
            return new Map<String, Schema.SObjectField>();
        }
        
        // Get field map
        Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
        fieldMapCache.put(cacheKey, fieldMap);
        
        return fieldMap;
    }
    
    /**
     * @description Gets child relationships for an object
     * @param objectApiName The API name of the object
     * @return List<Schema.ChildRelationship> The child relationships
     */
    public static List<Schema.ChildRelationship> getChildRelationships(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return new List<Schema.ChildRelationship>();
        }
        
        String cacheKey = objectApiName.toLowerCase();
        
        // Check cache
        if (childRelCache.containsKey(cacheKey)) {
            return childRelCache.get(cacheKey);
        }
        
        // Get describe result
        Schema.DescribeSObjectResult describeResult = getDescribe(objectApiName);
        if (describeResult == null) {
            return new List<Schema.ChildRelationship>();
        }
        
        // Get child relationships
        List<Schema.ChildRelationship> childRelationships = describeResult.getChildRelationships();
        childRelCache.put(cacheKey, childRelationships);
        
        return childRelationships;
    }
    
    /**
     * @description Gets field describe for a specific field
     * @param objectApiName The object API name
     * @param fieldApiName The field API name
     * @return Schema.DescribeFieldResult The field describe or null
     */
    public static Schema.DescribeFieldResult getFieldDescribe(String objectApiName, String fieldApiName) {
        Map<String, Schema.SObjectField> fieldMap = getFieldMap(objectApiName);
        
        if (fieldMap.containsKey(fieldApiName.toLowerCase())) {
            return fieldMap.get(fieldApiName.toLowerCase()).getDescribe();
        }
        
        return null;
    }
    
    /**
     * @description Checks if a field is accessible
     * @param objectApiName The object API name
     * @param fieldApiName The field API name
     * @return Boolean True if accessible
     */
    public static Boolean isFieldAccessible(String objectApiName, String fieldApiName) {
        Schema.DescribeFieldResult fieldDescribe = getFieldDescribe(objectApiName, fieldApiName);
        return fieldDescribe != null && fieldDescribe.isAccessible();
    }
    
    /**
     * @description Checks if an object is accessible
     * @param objectApiName The object API name
     * @return Boolean True if accessible
     */
    public static Boolean isObjectAccessible(String objectApiName) {
        Schema.DescribeSObjectResult describeResult = getDescribe(objectApiName);
        return describeResult != null && describeResult.isAccessible();
    }
    
    /**
     * @description Clears all caches (for testing)
     */
    @TestVisible
    private static void clearCache() {
        sObjectTypeCache.clear();
        describeCache.clear();
        fieldMapCache.clear();
        childRelCache.clear();
        nonExistentObjects.clear();
    }
}
