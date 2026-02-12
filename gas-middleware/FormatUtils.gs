/**
 * FormatUtils - Value formatting utilities
 * Version 1.0
 */
const FormatUtils = {

  _fieldTypesMap: null,

  setFieldTypes: function(fieldTypes) {
    this._fieldTypesMap = fieldTypes || null;
    if (fieldTypes) {
      logDebug('FormatUtils: Loaded ' + Object.keys(fieldTypes).length + ' field types for auto-formatting');
    }
  },

  getAutoFormat: function(fieldPath) {
    if (!this._fieldTypesMap || !fieldPath) {
      return null;
    }

    // Try exact match first
    if (this._fieldTypesMap[fieldPath]) {
      return this._fieldTypesMap[fieldPath];
    }

    // Try just the field name (last part of path)
    const parts = fieldPath.split('.');
    const fieldName = parts[parts.length - 1];
    if (this._fieldTypesMap[fieldName]) {
      return this._fieldTypesMap[fieldName];
    }

    return null;
  },

  formatValue: function(value, format, fieldPath) {
    if (value === null || value === undefined) {
      return '';
    }

    // If no explicit format, try auto-format from field types
    if (!format && fieldPath) {
      const autoFormat = this.getAutoFormat(fieldPath);
      if (autoFormat) {
        format = autoFormat;
        // logDebug('Auto-formatting ' + fieldPath + ' as ' + autoFormat);
      }
    }

    if (!format) {
      return this.defaultFormat(value);
    }

    const formatLower = format.toLowerCase();

    switch (formatLower) {
      case 'currency':
      case 'money':
        return this.formatCurrency(value);

      case 'number':
      case 'numeric':
        return this.formatNumber(value);

      case 'percent':
      case 'percentage':
        return this.formatPercent(value);

      case 'date':
        return this.formatDate(value);

      case 'datetime':
        return this.formatDateTime(value);

      case 'time':
        return this.formatTime(value);

      case 'uppercase':
      case 'upper':
        return String(value).toUpperCase();

      case 'lowercase':
      case 'lower':
        return String(value).toLowerCase();

      case 'capitalize':
      case 'title':
        return this.titleCase(value);

      case 'phone':
        return this.formatPhone(value);

      case 'boolean':
      case 'yesno':
        return this.formatBoolean(value);

      default:
        // Check for decimal places format (e.g., "2" for 2 decimal places)
        if (/^\d+$/.test(format)) {
          return this.formatDecimal(value, parseInt(format));
        }
        return this.defaultFormat(value);
    }
  },

  defaultFormat: function(value) {
    if (value === null || value === undefined) {
      return '';
    }

    if (typeof value === 'boolean') {
      return value ? 'Yes' : 'No';
    }

    if (value instanceof Date) {
      return this.formatDate(value);
    }

    if (typeof value === 'object') {
      // Handle nested objects by returning a string representation
      if (Array.isArray(value)) {
        return value.join(', ');
      }
      return JSON.stringify(value);
    }

    return String(value);
  },

  formatCurrency: function(value) {
    const num = parseFloat(value);
    if (isNaN(num)) return value;

    // Check if value already has currency symbol
    const strValue = String(value);
    if (strValue.includes('$')) {
      // Already formatted, just clean up any double symbols
      return strValue.replace(/\$+/g, '$');
    }

    return '$' + num.toLocaleString('en-US', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    });
  },

  formatNumber: function(value) {
    const num = parseFloat(value);
    if (isNaN(num)) return value;

    return num.toLocaleString('en-US');
  },

  formatPercent: function(value) {
    const num = parseFloat(value);
    if (isNaN(num)) return value;

    // Assume value is already in percentage form (e.g., 25 for 25%)
    // If value < 1, assume it's decimal form (0.25 for 25%)
    const percent = num < 1 && num > -1 && num !== 0 ? num * 100 : num;

    return percent.toFixed(1) + '%';
  },

  formatDate: function(value) {
    const date = this.parseDate(value);
    if (!date) return value;

    return date.toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric'
    });
  },

  formatDateTime: function(value) {
    const date = this.parseDate(value);
    if (!date) return value;

    return date.toLocaleString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: 'numeric',
      minute: '2-digit'
    });
  },

  formatTime: function(value) {
    const date = this.parseDate(value);
    if (!date) return value;

    return date.toLocaleTimeString('en-US', {
      hour: 'numeric',
      minute: '2-digit'
    });
  },

  parseDate: function(value) {
    if (value instanceof Date) {
      return value;
    }

    if (typeof value === 'string') {
      // Try ISO format first
      const isoDate = new Date(value);
      if (!isNaN(isoDate.getTime())) {
        return isoDate;
      }

      // Try MM/DD/YYYY
      const parts = value.split('/');
      if (parts.length === 3) {
        const date = new Date(parts[2], parts[0] - 1, parts[1]);
        if (!isNaN(date.getTime())) {
          return date;
        }
      }
    }

    if (typeof value === 'number') {
      // Assume milliseconds timestamp
      return new Date(value);
    }

    return null;
  },

  titleCase: function(value) {
    return String(value)
      .toLowerCase()
      .replace(/\b\w/g, char => char.toUpperCase());
  },

  formatPhone: function(value) {
    const digits = String(value).replace(/\D/g, '');

    if (digits.length === 10) {
      return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
    }

    if (digits.length === 11 && digits.startsWith('1')) {
      return `+1 (${digits.slice(1, 4)}) ${digits.slice(4, 7)}-${digits.slice(7)}`;
    }

    return value;
  },

  formatBoolean: function(value) {
    if (typeof value === 'boolean') {
      return value ? 'Yes' : 'No';
    }

    const strVal = String(value).toLowerCase();
    if (['true', '1', 'yes', 'y'].includes(strVal)) {
      return 'Yes';
    }
    if (['false', '0', 'no', 'n', ''].includes(strVal)) {
      return 'No';
    }

    return value;
  },

  formatDecimal: function(value, places) {
    const num = parseFloat(value);
    if (isNaN(num)) return value;

    return num.toFixed(places);
  }
};
