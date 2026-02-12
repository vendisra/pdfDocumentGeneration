/**
 * Salesforce Document Generation - Google Apps Script Middleware
 * Version 1.0
 *
 * Receives requests from Salesforce, processes Google Docs templates, returns PDFs.
 * Deploy as Web App: Execute as "Me", Access: "Anyone"
 */

var DEBUG_INFO = [];

const CONFIG = {
  VERSION: '1.0',
  API_KEY: null,  // Optional security key
  WORKING_FOLDER_ID: null,  // Optional Drive folder for temp files
  LOG_LEVEL: 'INFO',
  MAX_EXECUTION_TIME_MS: 300000
};

function doGet(e) {
  if (!e || !e.parameter) {
    return createJsonResponse({
      success: true,
      message: 'Document Generator running. Use POST for generation.',
      version: CONFIG.VERSION
    });
  }

  if (e.parameter.action === 'health') {
    return createJsonResponse({
      success: true,
      status: 'healthy',
      timestamp: new Date().toISOString(),
      version: CONFIG.VERSION,
      apiKeyRequired: CONFIG.API_KEY !== null
    });
  }

  return createJsonResponse({
    success: false,
    error: 'Use POST for document generation'
  });
}

function doPost(e) {
  const startTime = Date.now();

  try {
    if (!e || !e.postData) {
      return createJsonResponse({ success: false, error: 'No request body' });
    }

    let request;
    try {
      request = JSON.parse(e.postData.contents);
    } catch (parseError) {
      return createJsonResponse({ success: false, error: 'Invalid JSON: ' + parseError.message });
    }

    if (CONFIG.API_KEY) {
      const providedKey = request.apiKey || (e.parameter && e.parameter.key);
      if (providedKey !== CONFIG.API_KEY) {
        logWarn('Invalid API key');
        return createJsonResponse({ success: false, error: 'Invalid API key' });
      }
    }

    const action = request.action || 'generate';
    switch (action) {
      case 'generate': return handleGenerate(request, startTime);
      case 'validate': return handleValidate(request);
      default: return createJsonResponse({ success: false, error: 'Unknown action: ' + action });
    }

  } catch (error) {
    logError('doPost failed', error);
    return createJsonResponse({
      success: false,
      error: error.message,
      stack: CONFIG.LOG_LEVEL === 'DEBUG' ? error.stack : undefined
    });
  }
}

function handleGenerate(request, startTime) {
  const warnings = [];
  let workingCopyId = null;

  DEBUG_INFO = [];

  if (!DocumentService.canUploadToSalesforce()) {
    return createJsonResponse({
      success: false,
      error: 'Salesforce JWT auth not configured. Set SF_* properties in Script Properties.',
      gasVersion: CONFIG.VERSION
    });
  }

  const directUpload = request.directUpload || {};

  try {
    if (!request.templateId) throw new Error('templateId required');
    if (!directUpload.parentRecordId) throw new Error('parentRecordId required');

    logInfo('Starting generation for template: ' + request.templateId);

    workingCopyId = DocumentService.createWorkingCopy(
      request.templateId,
      request.outputFileName || 'Document'
    );

    const processResult = TemplateProcessor.processDocument(
      workingCopyId,
      request.recordData || {},
      request.childData || {},
      request.systemVariables || {},
      request.additionalFields || {},
      request.crossObjectData || {}
    );

    warnings.push(...processResult.warnings);

    const pdfBlob = DocumentService.exportAsPdf(workingCopyId);
    const fileName = request.outputFileName || 'Document';

    DocumentService.deleteFile(workingCopyId);
    workingCopyId = null;

    const uploadResult = DocumentService.uploadToSalesforce(
      pdfBlob,
      fileName,
      directUpload.parentRecordId
    );

    if (!uploadResult.success) {
      throw new Error('Upload failed: ' + uploadResult.error);
    }

    logInfo('Generation complete in ' + (Date.now() - startTime) + 'ms');

    return createJsonResponse({
      success: true,
      uploadedDirectly: true,
      contentDocumentId: uploadResult.contentDocumentId,
      contentVersionId: uploadResult.contentVersionId,
      fileName: fileName + '.pdf',
      warnings: warnings,
      processingTimeMs: Date.now() - startTime,
      gasVersion: CONFIG.VERSION,
      debugInfo: DEBUG_INFO
    });

  } catch (error) {
    if (workingCopyId) {
      try { DocumentService.deleteFile(workingCopyId); } catch (e) {}
    }

    logError('Generation failed', error);

    return createJsonResponse({
      success: false,
      error: error.message,
      warnings: warnings,
      processingTimeMs: Date.now() - startTime
    });
  }
}

function handleValidate(request) {
  try {
    if (!request.templateId) throw new Error('templateId required');

    const validation = TemplateProcessor.validateTemplate(request.templateId);

    return createJsonResponse({
      success: true,
      isValid: validation.isValid,
      requiredFields: validation.fields,
      childRelationships: validation.childRelationships,
      errors: validation.errors,
      warnings: validation.warnings,
      templateText: validation.templateText
    });

  } catch (error) {
    logError('Validation failed', error);
    return createJsonResponse({ success: false, error: error.message });
  }
}

function createJsonResponse(data) {
  const output = ContentService.createTextOutput(JSON.stringify(data));
  output.setMimeType(ContentService.MimeType.JSON);
  return output;
}

function logDebug(message, data) {
  if (CONFIG.LOG_LEVEL === 'DEBUG') console.log('[DEBUG] ' + message, data || '');
}

function logInfo(message, data) {
  if (['DEBUG', 'INFO'].includes(CONFIG.LOG_LEVEL)) console.log('[INFO] ' + message, data || '');
}

function logWarn(message, data) {
  if (['DEBUG', 'INFO', 'WARN'].includes(CONFIG.LOG_LEVEL)) console.warn('[WARN] ' + message, data || '');
}

function logError(message, error) {
  console.error('[ERROR] ' + message, error);
}

function testDeployment() {
  console.log('Testing deployment...');
  console.log('API Key: ' + (CONFIG.API_KEY !== null));
  console.log('Version: ' + CONFIG.VERSION);
  const result = doGet({ parameter: { action: 'health' } });
  console.log('Health check: ' + result.getContent());
}
