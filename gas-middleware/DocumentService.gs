/**
 * DocumentService - Google Drive/Docs operations and Salesforce upload
 * Version 1.0
 */
const DocumentService = {

  SF_API_VERSION: 'v60.0',

  createWorkingCopy: function(templateId, name) {
    try {
      // Validate template ID
      if (!templateId || templateId.trim() === '') {
        throw new Error('Template ID is required');
      }
      
      // Get the template file
      let template;
      try {
        template = DriveApp.getFileById(templateId);
      } catch (e) {
        throw new Error('Template not found. Check that the Google Doc ID "' + templateId + '" is correct and accessible.');
      }
      
      // Verify it's a Google Doc
      const mimeType = template.getMimeType();
      if (mimeType !== 'application/vnd.google-apps.document') {
        throw new Error('Template is not a Google Doc. Found type: ' + mimeType);
      }
      
      const copyName = `${name}_${Date.now()}`;
      let workingCopy;
      
      // Try to use configured working folder, fall back to template's folder
      if (CONFIG.WORKING_FOLDER_ID) {
        try {
          const folder = DriveApp.getFolderById(CONFIG.WORKING_FOLDER_ID);
          workingCopy = template.makeCopy(copyName, folder);
          logDebug('Created working copy in configured folder: ' + CONFIG.WORKING_FOLDER_ID);
        } catch (folderError) {
          // Folder not accessible, fall back to template's folder
          logWarn('Could not use WORKING_FOLDER_ID (' + CONFIG.WORKING_FOLDER_ID + '): ' + folderError.message + '. Using template folder instead.');
          workingCopy = this.copyToTemplateFolder(template, copyName);
        }
      } else {
        // No working folder configured, copy to template's folder
        workingCopy = this.copyToTemplateFolder(template, copyName);
      }
      
      logDebug('Created working copy: ' + workingCopy.getId());
      return workingCopy.getId();
      
    } catch (error) {
      throw new Error('Failed to create working copy: ' + error.message);
    }
  },
  
  copyToTemplateFolder: function(template, copyName) {
    // Get template's parent folders
    const parents = template.getParents();
    
    if (parents.hasNext()) {
      const parentFolder = parents.next();
      logDebug('Copying to template folder: ' + parentFolder.getName());
      return template.makeCopy(copyName, parentFolder);
    } else {
      // No parent folder (rare), copy to root
      logDebug('Copying to My Drive root');
      return template.makeCopy(copyName);
    }
  },
  
  getDocument: function(docId) {
    try {
      return DocumentApp.openById(docId);
    } catch (e) {
      throw new Error('Could not open document: ' + e.message);
    }
  },
  
  exportAsPdf: function(docId) {
    try {
      // Save and close the document first
      const doc = DocumentApp.openById(docId);
      doc.saveAndClose();

      Utilities.sleep(100); // Reduced from 500ms
      const url = 'https://docs.google.com/document/d/' + docId + '/export?format=pdf';
      const maxRetries = 3;
      let lastError = null;

      for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          logDebug('PDF export attempt ' + attempt + '/' + maxRetries);

          const response = UrlFetchApp.fetch(url, {
            headers: {
              Authorization: 'Bearer ' + ScriptApp.getOAuthToken()
            },
            muteHttpExceptions: true
          });

          const responseCode = response.getResponseCode();

          if (responseCode === 200) {
            logInfo('PDF exported successfully on attempt ' + attempt);
            return response.getBlob().setName('document.pdf');
          }

          // Non-200 response
          lastError = new Error('PDF export returned status ' + responseCode + ': ' + response.getContentText().substring(0, 200));
          logWarn('PDF export attempt ' + attempt + ' failed: ' + lastError.message);

        } catch (fetchError) {
          lastError = fetchError;
          logWarn('PDF export attempt ' + attempt + ' threw error: ' + fetchError.message);
        }

        // Wait before retry (exponential backoff)
        if (attempt < maxRetries) {
          const retryDelay = attempt * 200; // 200ms, 400ms
          logDebug('Retrying after ' + retryDelay + 'ms...');
          Utilities.sleep(retryDelay);
        }
      }

      // All retries failed
      throw new Error('PDF export failed after ' + maxRetries + ' attempts. Last error: ' + (lastError ? lastError.message : 'Unknown'));

    } catch (error) {
      throw new Error('Failed to export PDF: ' + error.message);
    }
  },
  
  deleteFile: function(fileId) {
    try {
      const file = DriveApp.getFileById(fileId);
      file.setTrashed(true);
      logDebug('Deleted file: ' + fileId);
    } catch (error) {
      logWarn('Failed to delete file ' + fileId + ': ' + error.message);
      // Don't throw - cleanup failure shouldn't fail the whole operation
    }
  },
  
  getBody: function(docId) {
    const doc = DocumentApp.openById(docId);
    return doc.getBody();
  },
  
  validateTemplate: function(templateId) {
    try {
      const file = DriveApp.getFileById(templateId);
      const mimeType = file.getMimeType();
      
      if (mimeType !== 'application/vnd.google-apps.document') {
        return {
          isValid: false,
          message: 'File is not a Google Doc. Type: ' + mimeType
        };
      }
      
      // Try to open it
      DocumentApp.openById(templateId);
      
      return {
        isValid: true,
        message: 'Template is valid and accessible',
        name: file.getName()
      };
      
    } catch (e) {
      return {
        isValid: false,
        message: 'Cannot access template: ' + e.message
      };
    }
  },
  
  uploadToSalesforce: function(pdfBlob, fileName, parentRecordId) {
    const result = {
      success: false,
      contentDocumentId: null,
      contentVersionId: null,
      error: null
    };
    
    try {
      // Get Salesforce auth
      if (!SalesforceAuth.isConfigured()) {
        throw new Error('Salesforce authentication not configured. Set SF_* properties in Script Properties.');
      }
      
      const auth = SalesforceAuth.getAccessToken();
      logInfo('Uploading PDF directly to Salesforce: ' + fileName);
      
      // Step 1: Create ContentVersion (the file)
      const cvResult = this.createContentVersion(auth, pdfBlob, fileName);
      result.contentVersionId = cvResult.id;
      logDebug('Created ContentVersion: ' + cvResult.id);
      
      // Step 2: Query for ContentDocumentId
      result.contentDocumentId = this.getContentDocumentId(auth, cvResult.id);
      logDebug('ContentDocumentId: ' + result.contentDocumentId);
      
      // Step 3: Create ContentDocumentLink to attach to record
      if (parentRecordId) {
        this.createContentDocumentLink(auth, result.contentDocumentId, parentRecordId);
        logDebug('Linked document to record: ' + parentRecordId);
      }
      
      result.success = true;
      logInfo('Successfully uploaded PDF to Salesforce');
      
    } catch (error) {
      result.error = error.message;
      logError('Salesforce upload failed', error);
    }
    
    return result;
  },
  
  createContentVersion: function(auth, pdfBlob, fileName) {
    const endpoint = auth.instanceUrl + '/services/data/' + this.SF_API_VERSION + '/sobjects/ContentVersion';
    
    // Build multipart form data
    const boundary = '----SalesforceUpload' + Date.now();
    const pdfBytes = pdfBlob.getBytes();
    const pdfBase64 = Utilities.base64Encode(pdfBytes);
    
    // ContentVersion JSON metadata
    const metadata = {
      Title: fileName,
      PathOnClient: fileName + '.pdf',
      VersionData: pdfBase64
    };
    
    // Make request
    const response = UrlFetchApp.fetch(endpoint, {
      method: 'POST',
      headers: {
        'Authorization': 'Bearer ' + auth.accessToken,
        'Content-Type': 'application/json'
      },
      payload: JSON.stringify(metadata),
      muteHttpExceptions: true
    });
    
    const responseCode = response.getResponseCode();
    const responseBody = response.getContentText();
    
    if (responseCode !== 201) {
      this.handleSalesforceError('ContentVersion creation', responseCode, responseBody);
    }
    
    return JSON.parse(responseBody);
  },
  
  getContentDocumentId: function(auth, contentVersionId) {
    const query = encodeURIComponent(
      "SELECT ContentDocumentId FROM ContentVersion WHERE Id = '" + contentVersionId + "'"
    );
    const endpoint = auth.instanceUrl + '/services/data/' + this.SF_API_VERSION + '/query?q=' + query;
    
    const response = UrlFetchApp.fetch(endpoint, {
      method: 'GET',
      headers: {
        'Authorization': 'Bearer ' + auth.accessToken
      },
      muteHttpExceptions: true
    });
    
    const responseCode = response.getResponseCode();
    const responseBody = response.getContentText();
    
    if (responseCode !== 200) {
      this.handleSalesforceError('ContentDocumentId query', responseCode, responseBody);
    }
    
    const result = JSON.parse(responseBody);
    
    if (!result.records || result.records.length === 0) {
      throw new Error('ContentDocumentId not found for ContentVersion: ' + contentVersionId);
    }
    
    return result.records[0].ContentDocumentId;
  },
  
  createContentDocumentLink: function(auth, contentDocumentId, linkedEntityId) {
    const endpoint = auth.instanceUrl + '/services/data/' + this.SF_API_VERSION + '/sobjects/ContentDocumentLink';
    
    const linkData = {
      ContentDocumentId: contentDocumentId,
      LinkedEntityId: linkedEntityId,
      ShareType: 'V',      // Viewer permission
      Visibility: 'AllUsers'
    };
    
    const response = UrlFetchApp.fetch(endpoint, {
      method: 'POST',
      headers: {
        'Authorization': 'Bearer ' + auth.accessToken,
        'Content-Type': 'application/json'
      },
      payload: JSON.stringify(linkData),
      muteHttpExceptions: true
    });
    
    const responseCode = response.getResponseCode();
    const responseBody = response.getContentText();
    
    if (responseCode !== 201) {
      // ContentDocumentLink creation might fail if link already exists
      // This is not fatal - the file is still uploaded
      logWarn('ContentDocumentLink creation returned ' + responseCode + ': ' + responseBody);
    }
  },
  
  handleSalesforceError: function(operation, statusCode, responseBody) {
    let errorMessage = operation + ' failed with status ' + statusCode;
    
    try {
      const errorData = JSON.parse(responseBody);
      if (Array.isArray(errorData) && errorData.length > 0) {
        errorMessage += ': ' + (errorData[0].message || errorData[0].errorCode || JSON.stringify(errorData[0]));
      } else if (errorData.message) {
        errorMessage += ': ' + errorData.message;
      } else {
        errorMessage += ': ' + responseBody.substring(0, 200);
      }
    } catch (e) {
      errorMessage += ': ' + responseBody.substring(0, 200);
    }
    
    throw new Error(errorMessage);
  },
  
  canUploadToSalesforce: function() {
    return SalesforceAuth.isConfigured();
  }
};
