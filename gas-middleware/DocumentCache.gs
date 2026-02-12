/**
 * DocumentCache - Minimizes API calls by caching text reads
 * Version 1.0
 */
const DocumentCache = {

  _cache: {},
  _stats: {
    hits: 0,
    misses: 0,
    invalidations: 0
  },

  getBodyText: function(body) {
    try {
      const parent = body.getParent();
      const docId = parent.getId();
      const cacheKey = docId + '_body_text';

      if (this._cache[cacheKey]) {
        this._stats.hits++;
        logDebug('DocumentCache HIT: body text');
        return this._cache[cacheKey];
      }

      this._stats.misses++;
      logDebug('DocumentCache MISS: body text (reading from API)');
      const text = body.getText();
      this._cache[cacheKey] = text;
      return text;
    } catch (e) {
      // If we can't get document ID (getId() not available), just read without caching
      logDebug('DocumentCache: Cannot get document ID, reading without cache: ' + e.message);
      return body.getText();
    }
  },

  getParagraphText: function(paragraph, index) {
    // Generate unique cache key
    const parent = paragraph.getParent();
    let docId;

    try {
      // Try to get document ID from parent chain
      if (parent.getType() === DocumentApp.ElementType.BODY_SECTION) {
        docId = parent.asBody().getParent().getId();
      } else {
        // For table cells or other nested elements, use a generic key
        docId = 'unknown';
      }
    } catch (e) {
      docId = 'unknown';
    }

    const cacheKey = docId + '_paragraph_' + index;

    if (this._cache[cacheKey]) {
      this._stats.hits++;
      return this._cache[cacheKey];
    }

    this._stats.misses++;
    const text = paragraph.getText();
    this._cache[cacheKey] = text;
    return text;
  },

  getCellText: function(cell, rowIndex, cellIndex) {
    const cacheKey = 'cell_' + rowIndex + '_' + cellIndex;

    if (this._cache[cacheKey]) {
      this._stats.hits++;
      return this._cache[cacheKey];
    }

    this._stats.misses++;
    const text = cell.getText();
    this._cache[cacheKey] = text;
    return text;
  },

  invalidateBody: function(body) {
    try {
      const docId = body.getParent().getId();
      const cacheKey = docId + '_body_text';

      if (this._cache[cacheKey]) {
        delete this._cache[cacheKey];
        this._stats.invalidations++;
        logDebug('DocumentCache INVALIDATED: body text');
      }
    } catch (e) {
      // If we can't get document ID, skip invalidation (no cache to invalidate)
      logDebug('DocumentCache: Cannot invalidate - no document ID available');
    }
  },

  invalidateParagraphs: function() {
    let count = 0;
    for (const key in this._cache) {
      if (key.indexOf('_paragraph_') !== -1) {
        delete this._cache[key];
        count++;
      }
    }
    if (count > 0) {
      this._stats.invalidations += count;
      logDebug('DocumentCache INVALIDATED: ' + count + ' paragraphs');
    }
  },

  clearAll: function() {
    const cacheSize = Object.keys(this._cache).length;

    if (cacheSize > 0) {
      logDebug('DocumentCache: Clearing ' + cacheSize + ' cached items');
    }

    this._cache = {};
    this._stats = {
      hits: 0,
      misses: 0,
      invalidations: 0
    };
  },

  getStats: function() {
    const totalAccess = this._stats.hits + this._stats.misses;
    const hitRate = totalAccess > 0 ? (this._stats.hits / totalAccess * 100).toFixed(1) : 0;

    return {
      hits: this._stats.hits,
      misses: this._stats.misses,
      invalidations: this._stats.invalidations,
      hitRate: hitRate + '%',
      apiCallsSaved: this._stats.hits
    };
  },

  logStats: function() {
    const stats = this.getStats();

    if (stats.hits > 0 || stats.misses > 0) {
      logInfo('DocumentCache stats: ' + stats.hits + ' hits, ' +
              stats.misses + ' misses (' + stats.hitRate + ' hit rate), ' +
              stats.apiCallsSaved + ' API calls saved');
    }
  }
};
