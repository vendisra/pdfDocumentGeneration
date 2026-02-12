/**
 * SalesforceAuth - JWT Bearer authentication for Salesforce REST API
 * Version 1.0
 */
const SalesforceAuth = {

  _tokenCache: null,
  _tokenExpiry: null,
  TOKEN_CACHE_DURATION_MS: 10 * 60 * 1000,

  getAccessToken: function() {
    // Check cache first
    if (this._tokenCache && this._tokenExpiry && Date.now() < this._tokenExpiry) {
      logDebug('Using cached Salesforce access token');
      return this._tokenCache;
    }
    
    // Get configuration from Script Properties
    const config = this.getConfig();
    
    // Generate JWT
    const jwt = this.generateJWT(config);
    
    // Exchange JWT for access token
    const tokenResponse = this.exchangeJWTForToken(jwt, config.loginUrl);
    
    // Cache the result
    this._tokenCache = {
      accessToken: tokenResponse.access_token,
      instanceUrl: tokenResponse.instance_url
    };
    this._tokenExpiry = Date.now() + this.TOKEN_CACHE_DURATION_MS;
    
    logInfo('Obtained new Salesforce access token');
    return this._tokenCache;
  },
  
  getConfig: function() {
    const props = PropertiesService.getScriptProperties();
    
    const config = {
      consumerKey: props.getProperty('SF_CONSUMER_KEY'),
      username: props.getProperty('SF_USERNAME'),
      loginUrl: props.getProperty('SF_LOGIN_URL'),
      privateKey: props.getProperty('SF_PRIVATE_KEY')
    };
    
    // Validate required properties
    const missing = [];
    if (!config.consumerKey) missing.push('SF_CONSUMER_KEY');
    if (!config.username) missing.push('SF_USERNAME');
    if (!config.loginUrl) missing.push('SF_LOGIN_URL');
    if (!config.privateKey) missing.push('SF_PRIVATE_KEY');
    
    if (missing.length > 0) {
      throw new Error(
        'Missing required Script Properties: ' + missing.join(', ') + '. ' +
        'Please configure these in File > Project properties > Script properties.'
      );
    }
    
    return config;
  },
  
  isConfigured: function() {
    try {
      this.getConfig();
      return true;
    } catch (e) {
      return false;
    }
  },
  
  generateJWT: function(config) {
    const now = Math.floor(Date.now() / 1000);
    
    // JWT Header
    const header = {
      alg: 'RS256',
      typ: 'JWT'
    };
    
    // JWT Payload (Claims)
    const payload = {
      iss: config.consumerKey,           // Issuer: Connected App consumer key
      sub: config.username,               // Subject: Service user's username
      aud: config.loginUrl,               // Audience: Salesforce login URL
      exp: now + 300                      // Expiration: 5 minutes from now
    };
    
    // Encode header and payload
    const encodedHeader = this.base64UrlEncode(JSON.stringify(header));
    const encodedPayload = this.base64UrlEncode(JSON.stringify(payload));
    
    // Create signature input
    const signatureInput = encodedHeader + '.' + encodedPayload;
    
    // Sign with RSA-SHA256
    const signature = this.signWithRSA(signatureInput, config.privateKey);
    
    return signatureInput + '.' + signature;
  },
  
  exchangeJWTForToken: function(jwt, loginUrl) {
    const tokenEndpoint = loginUrl + '/services/oauth2/token';
    
    const response = UrlFetchApp.fetch(tokenEndpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      payload: {
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: jwt
      },
      muteHttpExceptions: true
    });
    
    const responseCode = response.getResponseCode();
    const responseBody = response.getContentText();
    
    if (responseCode !== 200) {
      logError('JWT token exchange failed', { code: responseCode, body: responseBody });
      
      // Parse error for better message
      try {
        const errorData = JSON.parse(responseBody);
        throw new Error(
          'Salesforce authentication failed: ' + (errorData.error_description || errorData.error || responseBody)
        );
      } catch (e) {
        if (e.message.startsWith('Salesforce authentication')) throw e;
        throw new Error('Salesforce authentication failed: ' + responseBody);
      }
    }
    
    return JSON.parse(responseBody);
  },
  
  signWithRSA: function(data, privateKeyPem) {
    // Validate key format
    if (!privateKeyPem || typeof privateKeyPem !== 'string') {
      throw new Error('Private key is missing or not a string');
    }
    
    // Normalize the key - Script Properties can mangle line endings
    let normalizedKey = this.normalizePrivateKey(privateKeyPem);
    
    // Check for valid PEM format
    const hasPkcs8Header = normalizedKey.includes('-----BEGIN PRIVATE KEY-----');
    const hasRsaHeader = normalizedKey.includes('-----BEGIN RSA PRIVATE KEY-----');
    
    if (!hasPkcs8Header && !hasRsaHeader) {
      throw new Error(
        'Invalid private key format. Expected PEM format with ' +
        '"-----BEGIN PRIVATE KEY-----" or "-----BEGIN RSA PRIVATE KEY-----" header. ' +
        'Key starts with: ' + normalizedKey.substring(0, 50) + '...'
      );
    }
    
    try {
      // GAS computeRsaSha256Signature expects the PEM string directly
      const signature = Utilities.computeRsaSha256Signature(data, normalizedKey);
      return this.base64UrlEncode(signature);
    } catch (e) {
      // Provide helpful error message with key debug info
      const keyLength = normalizedKey.length;
      const lineCount = normalizedKey.split('\n').length;
      throw new Error(
        'RSA signing failed: ' + e.message + '. ' +
        'Key info: ' + keyLength + ' chars, ' + lineCount + ' lines, ' +
        'header: ' + (hasPkcs8Header ? 'PKCS#8' : hasRsaHeader ? 'PKCS#1' : 'none')
      );
    }
  },
  
  normalizePrivateKey: function(key) {
    // Remove any carriage returns (Windows line endings)
    let normalized = key.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    
    // Trim whitespace
    normalized = normalized.trim();
    
    // Handle keys that were pasted as a single line (Script Properties issue)
    // Check if the key is all on one line (no newlines between headers)
    if (normalized.includes('-----BEGIN') && !normalized.includes('\n')) {
      // Key is on single line - need to reformat
      logWarn('Private key appears to be on single line, reformatting...');
      normalized = this.reformatSingleLineKey(normalized);
    }
    
    // Ensure proper line breaks after headers and before footers
    normalized = normalized
      .replace(/(-----BEGIN [A-Z ]+-----)([^\n])/, '$1\n$2')
      .replace(/([^\n])(-----END [A-Z ]+-----)/, '$1\n$2');
    
    // Ensure base64 content has proper line length (64 chars per line)
    // This is required by some PEM parsers
    normalized = this.ensureProperPemLineLength(normalized);
    
    return normalized;
  },
  
  reformatSingleLineKey: function(key) {
    // Extract the header, content, and footer
    const headerMatch = key.match(/(-----BEGIN [A-Z ]+-----)/);
    const footerMatch = key.match(/(-----END [A-Z ]+-----)/);
    
    if (!headerMatch || !footerMatch) {
      return key; // Can't parse, return as-is
    }
    
    const header = headerMatch[1];
    const footer = footerMatch[1];
    
    // Extract the base64 content between header and footer
    const headerEnd = key.indexOf(header) + header.length;
    const footerStart = key.indexOf(footer);
    let content = key.substring(headerEnd, footerStart).trim();
    
    // Remove any spaces that might have been added
    content = content.replace(/\s/g, '');
    
    // Split into 64-character lines
    const lines = [];
    for (let i = 0; i < content.length; i += 64) {
      lines.push(content.substring(i, i + 64));
    }
    
    return header + '\n' + lines.join('\n') + '\n' + footer;
  },
  
  ensureProperPemLineLength: function(pem) {
    const lines = pem.split('\n');
    const result = [];
    
    for (const line of lines) {
      // Keep header/footer lines as-is
      if (line.startsWith('-----')) {
        result.push(line);
      } else if (line.trim().length > 0) {
        // This is base64 content - ensure 64 char lines
        const content = line.replace(/\s/g, '');
        for (let i = 0; i < content.length; i += 64) {
          result.push(content.substring(i, i + 64));
        }
      }
    }
    
    return result.join('\n');
  },
  
  base64UrlEncode: function(data) {
    let base64;
    
    if (typeof data === 'string') {
      base64 = Utilities.base64Encode(data);
    } else {
      // Byte array
      base64 = Utilities.base64Encode(data);
    }
    
    // Convert to base64url (URL-safe)
    return base64
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '');
  },
  
  clearCache: function() {
    this._tokenCache = null;
    this._tokenExpiry = null;
    logInfo('Salesforce auth cache cleared');
  },
  
  testAuth: function() {
    const result = {
      success: false,
      configValid: false,
      tokenObtained: false,
      instanceUrl: null,
      error: null
    };
    
    try {
      // Test config
      const config = this.getConfig();
      result.configValid = true;
      
      // Clear cache to force fresh token
      this.clearCache();
      
      // Get token
      const auth = this.getAccessToken();
      result.tokenObtained = true;
      result.instanceUrl = auth.instanceUrl;
      result.success = true;
      
    } catch (e) {
      result.error = e.message;
    }
    
    return result;
  }
};

function testSalesforceAuth() {
  console.log('Testing Salesforce JWT Authentication...');
  
  const result = SalesforceAuth.testAuth();
  
  console.log('Config Valid: ' + result.configValid);
  console.log('Token Obtained: ' + result.tokenObtained);
  console.log('Instance URL: ' + result.instanceUrl);
  
  if (result.success) {
    console.log('✓ Authentication successful!');
  } else {
    console.log('✗ Authentication failed: ' + result.error);
  }
  
  return result;
}

function debugPrivateKey() {
  console.log('=== Private Key Debug ===');
  
  const props = PropertiesService.getScriptProperties();
  const rawKey = props.getProperty('SF_PRIVATE_KEY');
  
  if (!rawKey) {
    console.log('ERROR: SF_PRIVATE_KEY not found in Script Properties');
    return;
  }
  
  console.log('Raw key length: ' + rawKey.length + ' characters');
  console.log('Contains newlines: ' + rawKey.includes('\n'));
  console.log('Contains carriage returns: ' + rawKey.includes('\r'));
  console.log('First 100 chars: ' + rawKey.substring(0, 100));
  console.log('Last 100 chars: ' + rawKey.substring(rawKey.length - 100));
  
  // Check for common issues
  if (rawKey.includes('-----BEGIN CERTIFICATE-----')) {
    console.log('ERROR: This is a CERTIFICATE, not a PRIVATE KEY!');
    console.log('Export the KEYSTORE from Salesforce, not the certificate.');
    return;
  }
  
  if (!rawKey.includes('-----BEGIN')) {
    console.log('ERROR: Missing PEM header. Key should start with -----BEGIN PRIVATE KEY-----');
    return;
  }
  
  // Try to normalize and show result
  console.log('\n=== After Normalization ===');
  try {
    const normalized = SalesforceAuth.normalizePrivateKey(rawKey);
    const lines = normalized.split('\n');
    console.log('Normalized line count: ' + lines.length);
    console.log('First 3 lines:');
    lines.slice(0, 3).forEach((line, i) => console.log('  ' + i + ': ' + line.substring(0, 70) + (line.length > 70 ? '...' : '')));
    console.log('Last 3 lines:');
    lines.slice(-3).forEach((line, i) => console.log('  ' + (lines.length - 3 + i) + ': ' + line));
    
    // Try signing a test string
    console.log('\n=== Testing RSA Signature ===');
    const testData = 'test.data.string';
    const signature = SalesforceAuth.signWithRSA(testData, normalized);
    console.log('✓ RSA signing successful! Signature length: ' + signature.length);
    
  } catch (e) {
    console.log('ERROR during normalization/signing: ' + e.message);
  }
}
