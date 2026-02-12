/**
 * ImageHandler - Processes {{IMAGE:FieldName}} and {{IMAGE:FieldName:200x150}} markers
 * Version 1.0
 */
const ImageHandler = {

  IMAGE_PATTERN: /\{\{IMAGE:([^}:]+)(?::(\d+)x(\d+))?\}\}/gi,
  DEFAULT_WIDTH: 200,
  DEFAULT_HEIGHT: 200,
  MAX_WIDTH: 800,
  MAX_HEIGHT: 800,
  SUPPORTED_FORMATS: ['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp', 'image/svg+xml'],
  _imageCache: {},
  
  clearCache: function() {
    const cacheSize = Object.keys(this._imageCache).length;
    if (cacheSize > 0) logInfo('Clearing image cache (' + cacheSize + ' images)');
    this._imageCache = {};
  },

  processImages: function(body, mergeData) {
    const warnings = [];

    try {
      // Find all image markers by scanning paragraphs
      const imagePositions = this.findImageMarkers(body);

      if (imagePositions.length === 0) {
        return warnings; // No images to process
      }

      logInfo('Found ' + imagePositions.length + ' image marker(s)');

      // Process in reverse order to maintain element indices
      for (let i = imagePositions.length - 1; i >= 0; i--) {
        const pos = imagePositions[i];
        const result = this.processImageMarker(body, pos, mergeData);

        if (!result.success) {
          warnings.push(result.message);
        }
      }

      // Log cache statistics
      const cacheSize = Object.keys(this._imageCache).length;
      const cacheHits = imagePositions.length - cacheSize;
      if (cacheHits > 0) {
        logInfo('Image cache saved ' + cacheHits + ' HTTP request(s)');
      }

    } catch (error) {
      warnings.push('Error processing images: ' + error.message);
      logError('Image processing failed', error);
    }

    return warnings;
  },
  
  /**
   * Finds all image markers in the document
   * @param {GoogleAppsScript.Document.Body} body - Document body
   * @returns {Array} Array of image marker positions
   */
  findImageMarkers: function(body) {
    const positions = [];
    const numChildren = body.getNumChildren();
    
    for (let i = 0; i < numChildren; i++) {
      const child = body.getChild(i);
      
      if (child.getType() === DocumentApp.ElementType.PARAGRAPH) {
        const para = child.asParagraph();
        const text = para.getText();
        
        // Reset regex
        this.IMAGE_PATTERN.lastIndex = 0;
        let match;
        
        while ((match = this.IMAGE_PATTERN.exec(text)) !== null) {
          positions.push({
            elementIndex: i,
            paragraph: para,
            fullMatch: match[0],
            fieldName: match[1].trim(),
            width: match[2] ? parseInt(match[2]) : this.DEFAULT_WIDTH,
            height: match[3] ? parseInt(match[3]) : this.DEFAULT_HEIGHT,
            textBefore: text.substring(0, match.index),
            textAfter: text.substring(match.index + match[0].length)
          });
        }
      } else if (child.getType() === DocumentApp.ElementType.TABLE) {
        // Also check table cells
        const tablePositions = this.findImageMarkersInTable(child.asTable(), i);
        positions.push(...tablePositions);
      }
    }
    
    return positions;
  },
  
  /**
   * Finds image markers within a table
   * @param {GoogleAppsScript.Document.Table} table - Table element
   * @param {number} tableIndex - Index of table in body
   * @returns {Array} Array of image marker positions
   */
  findImageMarkersInTable: function(table, tableIndex) {
    const positions = [];
    const numRows = table.getNumRows();
    
    for (let r = 0; r < numRows; r++) {
      const row = table.getRow(r);
      const numCells = row.getNumCells();
      
      for (let c = 0; c < numCells; c++) {
        const cell = row.getCell(c);
        const text = cell.getText();
        
        this.IMAGE_PATTERN.lastIndex = 0;
        let match;
        
        while ((match = this.IMAGE_PATTERN.exec(text)) !== null) {
          positions.push({
            isTableCell: true,
            table: table,
            tableIndex: tableIndex,
            rowIndex: r,
            cellIndex: c,
            cell: cell,
            fullMatch: match[0],
            fieldName: match[1].trim(),
            width: match[2] ? parseInt(match[2]) : this.DEFAULT_WIDTH,
            height: match[3] ? parseInt(match[3]) : this.DEFAULT_HEIGHT
          });
        }
      }
    }
    
    return positions;
  },
  
  /**
   * Processes a single image marker
   * @param {GoogleAppsScript.Document.Body} body - Document body
   * @param {Object} pos - Position object from findImageMarkers
   * @param {Object} mergeData - Merged data for field resolution
   * @returns {Object} Result with success flag and message
   */
  processImageMarker: function(body, pos, mergeData) {
    try {
      // Resolve the image URL from merge data
      const imageUrl = TemplateProcessor.resolveValue(pos.fieldName, mergeData);
      
      if (!imageUrl || imageUrl === '') {
        logWarn('Image URL not found for field: ' + pos.fieldName);
        // Remove the marker
        this.removeImageMarker(body, pos);
        return {
          success: false,
          message: 'Image URL not found: ' + pos.fieldName
        };
      }
      
      // Validate URL format
      if (!this.isValidUrl(imageUrl)) {
        logWarn('Invalid image URL: ' + imageUrl);
        this.removeImageMarker(body, pos);
        return {
          success: false,
          message: 'Invalid image URL for ' + pos.fieldName + ': ' + imageUrl
        };
      }
      
      // Fetch and insert image
      const imageBlob = this.fetchImage(imageUrl);
      if (!imageBlob) {
        this.removeImageMarker(body, pos);
        return {
          success: false,
          message: 'Failed to fetch image from URL: ' + imageUrl
        };
      }
      
      // Validate dimensions
      const width = Math.min(pos.width, this.MAX_WIDTH);
      const height = Math.min(pos.height, this.MAX_HEIGHT);
      
      // Insert image based on location
      if (pos.isTableCell) {
        this.insertImageInTableCell(pos, imageBlob, width, height);
      } else {
        this.insertImageInParagraph(body, pos, imageBlob, width, height);
      }
      
      logInfo('Inserted image: ' + pos.fieldName + ' (' + width + 'x' + height + ')');
      
      return {
        success: true,
        message: 'Image inserted successfully'
      };
      
    } catch (error) {
      logError('Failed to process image marker: ' + pos.fieldName, error);
      this.removeImageMarker(body, pos);
      return {
        success: false,
        message: 'Error inserting image ' + pos.fieldName + ': ' + error.message
      };
    }
  },
  
  /**
   * Fetches an image from a URL with caching
   * @param {string} url - Image URL
   * @returns {GoogleAppsScript.Base.Blob} Image blob or null if failed
   */
  fetchImage: function(url) {
    if (!url) return null;

    // CHECK CACHE FIRST - Avoid duplicate HTTP requests
    if (this._imageCache[url]) {
      logDebug('Image cache HIT: ' + url);
      return this._imageCache[url];
    }

    try {
      logDebug('Image cache MISS - Fetching from: ' + url);

      const response = UrlFetchApp.fetch(url, {
        muteHttpExceptions: true,
        followRedirects: true,
        validateHttpsCertificates: true
      });

      const responseCode = response.getResponseCode();

      if (responseCode !== 200) {
        logWarn('Image fetch failed with status ' + responseCode + ': ' + url);
        return null;
      }

      const contentType = response.getHeaders()['Content-Type'] || '';

      if (!this.isSupportedImageFormat(contentType)) {
        logWarn('Unsupported image format: ' + contentType + ' for URL: ' + url);
        return null;
      }

      const blob = response.getBlob();

      // Verify blob has content
      if (!blob || blob.getBytes().length === 0) {
        logWarn('Empty image blob from URL: ' + url);
        return null;
      }

      // STORE IN CACHE for subsequent requests
      this._imageCache[url] = blob;
      logDebug('Cached image: ' + url);

      return blob;

    } catch (error) {
      logError('Failed to fetch image from ' + url, error);
      return null;
    }
  },
  
  /**
   * Inserts an image in a paragraph
   * @param {GoogleAppsScript.Document.Body} body - Document body
   * @param {Object} pos - Position object
   * @param {GoogleAppsScript.Base.Blob} imageBlob - Image blob
   * @param {number} width - Image width
   * @param {number} height - Image height
   */
  insertImageInParagraph: function(body, pos, imageBlob, width, height) {
    const para = pos.paragraph;
    const paraIndex = body.getChildIndex(para);
    
    // Check if marker is alone in paragraph
    const isAlone = pos.textBefore.trim() === '' && pos.textAfter.trim() === '';
    
    if (isAlone) {
      // Replace entire paragraph with image
      para.removeFromParent();
      const imagePara = body.insertParagraph(paraIndex, '');
      const inlineImage = imagePara.appendInlineImage(imageBlob);
      inlineImage.setWidth(width);
      inlineImage.setHeight(height);
      imagePara.setAlignment(DocumentApp.HorizontalAlignment.CENTER);
    } else {
      // Insert image inline with text
      // First, replace marker text with a placeholder
      const placeholder = '___IMAGE_PLACEHOLDER___';
      const newText = pos.textBefore + placeholder + pos.textAfter;
      para.setText(newText);
      
      // Find the placeholder position
      const paraText = para.editAsText();
      const placeholderIndex = newText.indexOf(placeholder);
      
      if (placeholderIndex !== -1) {
        // Remove placeholder text
        paraText.deleteText(placeholderIndex, placeholderIndex + placeholder.length - 1);
        
        // Insert image at that position
        const positionElement = para.getPositionedImages();
        // For inline images in paragraphs with text, we use appendInlineImage
        // and it goes at the end, so we need a different approach
        
        // Workaround: Split paragraph if needed
        if (pos.textAfter.trim() !== '') {
          // Create new paragraph with text after
          body.insertParagraph(paraIndex + 1, pos.textAfter);
        }
        
        // Set paragraph to text before
        para.setText(pos.textBefore);
        
        // Append image
        const inlineImage = para.appendInlineImage(imageBlob);
        inlineImage.setWidth(width);
        inlineImage.setHeight(height);
      }
    }
  },
  
  /**
   * Inserts an image in a table cell
   * @param {Object} pos - Position object
   * @param {GoogleAppsScript.Base.Blob} imageBlob - Image blob
   * @param {number} width - Image width
   * @param {number} height - Image height
   */
  insertImageInTableCell: function(pos, imageBlob, width, height) {
    const cell = pos.cell;
    
    // Clear cell content
    cell.clear();
    
    // Add image to cell
    const cellPara = cell.appendParagraph('');
    const inlineImage = cellPara.appendInlineImage(imageBlob);
    inlineImage.setWidth(width);
    inlineImage.setHeight(height);
    cellPara.setAlignment(DocumentApp.HorizontalAlignment.CENTER);
  },
  
  /**
   * Removes an image marker (when image can't be loaded)
   * @param {GoogleAppsScript.Document.Body} body - Document body
   * @param {Object} pos - Position object
   */
  removeImageMarker: function(body, pos) {
    try {
      if (pos.isTableCell) {
        // Remove marker text from cell
        const cell = pos.cell;
        const text = cell.getText();
        const newText = text.replace(pos.fullMatch, '[Image not available]');
        cell.setText(newText);
      } else {
        // Remove marker from paragraph
        const para = pos.paragraph;
        const text = para.getText();
        const newText = text.replace(pos.fullMatch, '');
        para.setText(newText);
      }
    } catch (error) {
      logWarn('Failed to remove image marker: ' + error.message);
    }
  },
  
  /**
   * Validates if a string is a valid URL
   * @param {string} url - URL to validate
   * @returns {boolean} True if valid
   */
  isValidUrl: function(url) {
    if (typeof url !== 'string') {
      return false;
    }
    
    // Basic URL validation
    return /^https?:\/\/.+\..+/i.test(url);
  },
  
  /**
   * Checks if content type is a supported image format
   * @param {string} contentType - MIME type
   * @returns {boolean} True if supported
   */
  isSupportedImageFormat: function(contentType) {
    if (!contentType) {
      return false;
    }
    
    const lowerType = contentType.toLowerCase().split(';')[0].trim();
    return this.SUPPORTED_FORMATS.includes(lowerType);
  }
};
