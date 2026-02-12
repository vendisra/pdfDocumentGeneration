/**
 * ExpressionEvaluator - Conditional expression parser with boolean logic
 * Version 1.0
 */
const ExpressionEvaluator = {

  evaluate: function(expression, data) {
    if (!expression || typeof expression !== 'string') {
      return false;
    }

    try {
      // Tokenize the expression
      const tokens = this.tokenize(expression);

      // Parse into expression tree
      const tree = this.parse(tokens);

      // Evaluate the tree
      return this.evaluateTree(tree, data);

    } catch (error) {
      logWarn('Expression evaluation error for "' + expression + '": ' + error.message);
      return false;
    }
  },

  tokenize: function(expression) {
    const tokens = [];
    let current = '';
    let inQuotes = false;
    let quoteChar = null;

    for (let i = 0; i < expression.length; i++) {
      const char = expression[i];
      const nextChar = i + 1 < expression.length ? expression[i + 1] : '';
      const next2Chars = i + 2 < expression.length ? expression.substring(i, i + 3) : '';

      // Handle quoted strings
      if ((char === '"' || char === "'") && !inQuotes) {
        inQuotes = true;
        quoteChar = char;
        current += char;
        continue;
      } else if (char === quoteChar && inQuotes) {
        inQuotes = false;
        current += char;
        tokens.push({type: 'VALUE', value: current});
        current = '';
        quoteChar = null;
        continue;
      }

      if (inQuotes) {
        current += char;
        continue;
      }

      // Handle parentheses
      if (char === '(') {
        if (current.trim()) {
          tokens.push({type: 'FIELD', value: current.trim()});
          current = '';
        }
        tokens.push({type: 'LPAREN', value: '('});
        continue;
      }

      if (char === ')') {
        if (current.trim()) {
          tokens.push({type: 'FIELD', value: current.trim()});
          current = '';
        }
        tokens.push({type: 'RPAREN', value: ')'});
        continue;
      }

      // Handle operators (>=, <=, ==, !=, >, <)
      if (char === '=' && nextChar === '=') {
        if (current.trim()) {
          tokens.push({type: 'FIELD', value: current.trim()});
          current = '';
        }
        tokens.push({type: 'OPERATOR', value: '=='});
        i++; // Skip next char
        continue;
      }

      if (char === '!' && nextChar === '=') {
        if (current.trim()) {
          tokens.push({type: 'FIELD', value: current.trim()});
          current = '';
        }
        tokens.push({type: 'OPERATOR', value: '!='});
        i++; // Skip next char
        continue;
      }

      if (char === '>' && nextChar === '=') {
        if (current.trim()) {
          tokens.push({type: 'FIELD', value: current.trim()});
          current = '';
        }
        tokens.push({type: 'OPERATOR', value: '>='});
        i++; // Skip next char
        continue;
      }

      if (char === '<' && nextChar === '=') {
        if (current.trim()) {
          tokens.push({type: 'FIELD', value: current.trim()});
          current = '';
        }
        tokens.push({type: 'OPERATOR', value: '<='});
        i++; // Skip next char
        continue;
      }

      if (char === '>') {
        if (current.trim()) {
          tokens.push({type: 'FIELD', value: current.trim()});
          current = '';
        }
        tokens.push({type: 'OPERATOR', value: '>'});
        continue;
      }

      if (char === '<') {
        if (current.trim()) {
          tokens.push({type: 'FIELD', value: current.trim()});
          current = '';
        }
        tokens.push({type: 'OPERATOR', value: '<'});
        continue;
      }

      // Handle whitespace - check for logical operators and string operators
      if (char === ' ') {
        const word = current.trim().toUpperCase();
        if (word === 'AND' || word === 'OR' || word === 'NOT') {
          tokens.push({type: word, value: word});
          current = '';
        } else if (word === 'CONTAINS' || word === 'STARTSWITH' || word === 'ENDSWITH' ||
                   word === 'ISBLANK' || word === 'IEQUALS') {
          tokens.push({type: 'STRING_OP', value: word});
          current = '';
        } else if (word === 'NULL' || word === 'TRUE' || word === 'FALSE') {
          tokens.push({type: 'VALUE', value: word});
          current = '';
        } else if (current.trim()) {
          // Not a keyword - emit as FIELD token and reset
          tokens.push({type: 'FIELD', value: current.trim()});
          current = '';
        }
        continue;
      }

      current += char;
    }

    // Add remaining token
    if (current.trim()) {
      const word = current.trim().toUpperCase();
      if (word === 'NULL' || word === 'TRUE' || word === 'FALSE') {
        tokens.push({type: 'VALUE', value: word});
      } else if (word === 'CONTAINS' || word === 'STARTSWITH' || word === 'ENDSWITH' ||
                 word === 'ISBLANK' || word === 'IEQUALS') {
        tokens.push({type: 'STRING_OP', value: word});
      } else {
        tokens.push({type: 'FIELD', value: current.trim()});
      }
    }

    return tokens;
  },

  parse: function(tokens) {
    let pos = 0;

    const parseOr = () => {
      let left = parseAnd();

      while (pos < tokens.length && tokens[pos].type === 'OR') {
        pos++; // consume OR
        const right = parseAnd();
        left = {type: 'OR', left: left, right: right};
      }

      return left;
    };

    const parseAnd = () => {
      let left = parseNot();

      while (pos < tokens.length && tokens[pos].type === 'AND') {
        pos++; // consume AND
        const right = parseNot();
        left = {type: 'AND', left: left, right: right};
      }

      return left;
    };

    const parseNot = () => {
      if (pos < tokens.length && tokens[pos].type === 'NOT') {
        pos++; // consume NOT
        const expr = parseNot(); // Allow chained NOTs
        return {type: 'NOT', expr: expr};
      }

      return parseComparison();
    };

    const parseComparison = () => {
      if (pos < tokens.length && tokens[pos].type === 'LPAREN') {
        pos++; // consume (
        const expr = parseOr();
        if (pos < tokens.length && tokens[pos].type === 'RPAREN') {
          pos++; // consume )
        }
        return expr;
      }

      // Parse comparison: field op value
      if (pos >= tokens.length) {
        throw new Error('Unexpected end of expression');
      }

      const firstToken = tokens[pos++];

      // Handle ISBLANK as prefix operator
      if (firstToken.type === 'STRING_OP' && firstToken.value === 'ISBLANK') {
        // ISBLANK is a unary operator that comes before the field
        if (pos >= tokens.length) {
          throw new Error('Expected field name after ISBLANK');
        }
        const fieldToken = tokens[pos++];
        return {
          type: 'STRING_OP',
          field: fieldToken.value,
          operator: 'ISBLANK',
          value: null
        };
      }

      // Handle boolean/null literals
      if (firstToken.type === 'VALUE') {
        // Handle boolean/null literals as truthy checks
        const upper = firstToken.value.toUpperCase();
        if (upper === 'TRUE' || upper === 'FALSE' || upper === 'NULL') {
          return {type: 'TRUTHY_LITERAL', value: firstToken.value};
        }
        throw new Error('Unexpected value token: ' + firstToken.value);
      }

      if (firstToken.type !== 'FIELD') {
        throw new Error('Expected field name, got: ' + firstToken.value);
      }

      // Check for operator or string operator
      if (pos >= tokens.length) {
        // No operator - truthy check
        return {type: 'TRUTHY', field: firstToken.value};
      }

      const nextToken = tokens[pos];

      if (nextToken.type === 'STRING_OP') {
        // String operator (CONTAINS, STARTSWITH, etc.)
        const operator = tokens[pos++];

        // ISBLANK doesn't require a value
        if (operator.value === 'ISBLANK') {
          return {
            type: 'STRING_OP',
            field: firstToken.value,
            operator: operator.value,
            value: null
          };
        }

        // Other string operators need a value
        if (pos >= tokens.length) {
          throw new Error('Expected value after ' + operator.value);
        }

        const value = tokens[pos++];

        return {
          type: 'STRING_OP',
          field: firstToken.value,
          operator: operator.value,
          value: value.value
        };
      } else if (nextToken.type === 'OPERATOR') {
        // Regular comparison operator
        const operator = tokens[pos++];

        if (pos >= tokens.length) {
          throw new Error('Expected value after operator');
        }

        const value = tokens[pos++];

        return {
          type: 'COMPARISON',
          field: firstToken.value,
          operator: operator.value,
          value: value.value
        };
      } else {
        // No operator - truthy check
        return {type: 'TRUTHY', field: firstToken.value};
      }
    };

    return parseOr();
  },

  evaluateTree: function(tree, data) {
    if (!tree) {
      return false;
    }

    switch (tree.type) {
      case 'OR':
        return this.evaluateTree(tree.left, data) || this.evaluateTree(tree.right, data);

      case 'AND':
        return this.evaluateTree(tree.left, data) && this.evaluateTree(tree.right, data);

      case 'NOT':
        return !this.evaluateTree(tree.expr, data);

      case 'COMPARISON':
        return this.evaluateComparison(tree.field, tree.operator, tree.value, data);

      case 'STRING_OP':
        return this.evaluateStringOperation(tree.field, tree.operator, tree.value, data);

      case 'TRUTHY':
        const value = this.resolveFieldValue(tree.field, data);
        return !!(value !== null && value !== undefined && value !== false && value !== '');

      case 'TRUTHY_LITERAL':
        const upper = tree.value.toUpperCase();
        if (upper === 'TRUE') return true;
        if (upper === 'FALSE') return false;
        if (upper === 'NULL') return false;
        return false;

      default:
        return false;
    }
  },

  evaluateStringOperation: function(fieldPath, operator, valueStr, data) {
    const fieldValue = this.resolveFieldValue(fieldPath, data);

    // Convert to string for string operations
    const fieldStr = fieldValue !== null && fieldValue !== undefined ? String(fieldValue) : '';

    switch (operator.toUpperCase()) {
      case 'CONTAINS':
        const searchStr = this.parseValue(valueStr);
        return fieldStr.indexOf(String(searchStr)) !== -1;

      case 'STARTSWITH':
        const prefixStr = this.parseValue(valueStr);
        return fieldStr.indexOf(String(prefixStr)) === 0;

      case 'ENDSWITH':
        const suffixStr = this.parseValue(valueStr);
        const suffix = String(suffixStr);
        return fieldStr.lastIndexOf(suffix) === fieldStr.length - suffix.length;

      case 'ISBLANK':
        return fieldValue === null || fieldValue === undefined ||
               (typeof fieldValue === 'string' && fieldValue.trim() === '');

      case 'IEQUALS':
        const compareStr = this.parseValue(valueStr);
        return fieldStr.toLowerCase() === String(compareStr).toLowerCase();

      default:
        return false;
    }
  },

  evaluateComparison: function(fieldPath, operator, valueStr, data) {
    const fieldValue = this.resolveFieldValue(fieldPath, data);

    // Resolve right-hand side as field if it looks like a field name
    let compareValue;
    if (this.isFieldReference(valueStr)) {
      compareValue = this.resolveFieldValue(valueStr, data);
    } else {
      compareValue = this.parseValue(valueStr);
    }

    switch (operator) {
      case '==':
        return fieldValue == compareValue;
      case '!=':
        return fieldValue != compareValue;
      case '>':
        return Number(fieldValue) > Number(compareValue);
      case '<':
        return Number(fieldValue) < Number(compareValue);
      case '>=':
        return Number(fieldValue) >= Number(compareValue);
      case '<=':
        return Number(fieldValue) <= Number(compareValue);
      default:
        return false;
    }
  },

  resolveFieldValue: function(fieldPath, data) {
    if (!fieldPath || !data) {
      return null;
    }

    const parts = fieldPath.trim().split('.');
    let value = data;

    for (let i = 0; i < parts.length; i++) {
      if (value === null || value === undefined) {
        return null;
      }
      if (typeof value === 'object') {
        value = value[parts[i]];
      } else {
        return null;
      }
    }

    return value;
  },

  parseValue: function(valueStr) {
    if (!valueStr) {
      return valueStr;
    }

    const trimmed = valueStr.trim();

    // Remove quotes
    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
        (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
      return trimmed.slice(1, -1);
    }

    // Special values
    const upper = trimmed.toUpperCase();
    if (upper === 'TRUE') return true;
    if (upper === 'FALSE') return false;
    if (upper === 'NULL') return null;

    // Try number - only if entire string is numeric
    if (/^-?\d+(\.\d+)?$/.test(trimmed)) {
      return parseFloat(trimmed);
    }

    return trimmed;
  },

  isFieldReference: function(valueStr) {
    if (!valueStr) return false;

    const trimmed = valueStr.trim();

    // If it has quotes, it's a literal
    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
        (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
      return false;
    }

    // If it's a known literal, it's not a field
    const upper = trimmed.toUpperCase();
    if (['TRUE', 'FALSE', 'NULL'].includes(upper)) {
      return false;
    }

    // If it's a number, it's not a field
    if (!isNaN(parseFloat(trimmed))) {
      return false;
    }

    // If it looks like a field name (contains letters/underscores/dots), it's a field
    return /^[a-zA-Z_][a-zA-Z0-9_\.]*$/.test(trimmed);
  }
};
