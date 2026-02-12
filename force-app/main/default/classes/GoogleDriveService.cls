/**
 * @description Service for storing generated PDFs in Salesforce Files.
 * Handles ContentVersion and ContentDocumentLink creation with proper security.
 * 
 * Note: Google Drive API operations are now handled by GAS middleware.
 * This class only handles the Salesforce Files storage.
 * 
 * @author Document Generation Framework
 * @since 2024
 */
public with sharing class GoogleDriveService {
    
    /**
     * @description Custom exception for file storage errors
     */
    public class FileStorageException extends Exception {}
    
    /**
     * @description Stores PDF blob in Salesforce Files and links to record
     * @param pdfBlob The PDF content as Blob
     * @param fileName The file name (will append .pdf if not present)
     * @param linkedEntityId The record ID to link the file to
     * @return Id The ContentDocument ID
     */
    public static Id storePdfInSalesforce(Blob pdfBlob, String fileName, Id linkedEntityId) {
        // Validate inputs
        if (pdfBlob == null) {
            throw new FileStorageException('PDF content is required');
        }
        if (String.isBlank(fileName)) {
            fileName = 'document_' + DateTime.now().getTime() + '.pdf';
        }
        
        // Verify CRUD permissions for ContentVersion
        if (!Schema.sObjectType.ContentVersion.isCreateable()) {
            throw new FileStorageException('Insufficient permissions: Cannot create ContentVersion records');
        }
        
        // Verify FLS for required ContentVersion fields
        if (!Schema.sObjectType.ContentVersion.fields.Title.isCreateable() ||
            !Schema.sObjectType.ContentVersion.fields.PathOnClient.isCreateable() ||
            !Schema.sObjectType.ContentVersion.fields.VersionData.isCreateable()) {
            throw new FileStorageException('Insufficient field-level permissions on ContentVersion');
        }
        
        // Ensure .pdf extension
        if (!fileName.toLowerCase().endsWith('.pdf')) {
            fileName += '.pdf';
        }
        
        // Sanitize filename
        fileName = sanitizeFileName(fileName);
        
        // Create ContentVersion
        ContentVersion cv = new ContentVersion();
        cv.Title = fileName.removeEnd('.pdf');
        cv.PathOnClient = fileName;
        cv.VersionData = pdfBlob;
        cv.Origin = 'H'; // Chatter
        
        Database.SaveResult sr = Database.insert(cv, AccessLevel.USER_MODE);
        if (!sr.isSuccess()) {
            String errorMsg = 'Failed to create ContentVersion: ';
            for (Database.Error err : sr.getErrors()) {
                errorMsg += err.getMessage() + '; ';
            }
            throw new FileStorageException(errorMsg);
        }
        
        // Query for ContentDocumentId
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id WITH USER_MODE LIMIT 1];
        
        // Link to entity if provided
        if (linkedEntityId != null) {
            linkToRecord(cv.ContentDocumentId, linkedEntityId);
        }
        
        return cv.ContentDocumentId;
    }
    
    /**
     * @description Links a ContentDocument to a record
     * @param contentDocumentId The ContentDocument ID
     * @param linkedEntityId The record ID to link to
     */
    public static void linkToRecord(Id contentDocumentId, Id linkedEntityId) {
        // Verify CRUD permissions for ContentDocumentLink
        if (!Schema.sObjectType.ContentDocumentLink.isCreateable()) {
            throw new FileStorageException('Insufficient permissions: Cannot create ContentDocumentLink records');
        }
        
        // Verify FLS for required ContentDocumentLink fields
        if (!Schema.sObjectType.ContentDocumentLink.fields.ContentDocumentId.isCreateable() ||
            !Schema.sObjectType.ContentDocumentLink.fields.LinkedEntityId.isCreateable() ||
            !Schema.sObjectType.ContentDocumentLink.fields.ShareType.isCreateable()) {
            throw new FileStorageException('Insufficient field-level permissions on ContentDocumentLink');
        }
        
        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = contentDocumentId;
        cdl.LinkedEntityId = linkedEntityId;
        cdl.ShareType = 'V'; // Viewer
        cdl.Visibility = 'AllUsers';
        
        Database.SaveResult cdlResult = Database.insert(cdl, AccessLevel.USER_MODE);
        if (!cdlResult.isSuccess()) {
            String errorMsg = 'Failed to create ContentDocumentLink: ';
            for (Database.Error err : cdlResult.getErrors()) {
                errorMsg += err.getMessage() + '; ';
            }
            throw new FileStorageException(errorMsg);
        }
    }
    
    /**
     * @description Sanitizes a filename by removing invalid characters
     * @param fileName The filename to sanitize
     * @return String The sanitized filename
     */
    private static String sanitizeFileName(String fileName) {
        if (String.isBlank(fileName)) {
            return 'document_' + DateTime.now().getTime() + '.pdf';
        }
        
        // Remove invalid characters
        fileName = fileName.replaceAll('[\\\\/:*?"<>|]', '_');
        fileName = fileName.replaceAll('\\s+', '_');
        
        // Ensure .pdf extension
        if (!fileName.toLowerCase().endsWith('.pdf')) {
            fileName += '.pdf';
        }
        
        // Limit length
        if (fileName.length() > 200) {
            fileName = fileName.substring(0, 196) + '.pdf';
        }
        
        return fileName;
    }
}
