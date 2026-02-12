/**
 * ConditionalProcessor - Handles {{IF}}...{{ELSEIF}}...{{ELSE}}...{{/IF}} blocks
 * Version 1.0
 */
const ConditionalProcessor = {

  processText: function(text, data, maxIterations) {
    if (!text || typeof text !== 'string') {
      return text || '';
    }

    maxIterations = maxIterations || 20;
    let iteration = 0;

    while (iteration < maxIterations) {
      iteration++;

      // Find innermost IF block
      const pattern = /\{\{IF\s+([^}]+)\}\}((?:(?!\{\{IF\s)[\s\S])*?)(?:\{\{ELSEIF\s+([^}]+)\}\}((?:(?!\{\{IF\s)[\s\S])*?))*(?:\{\{ELSE\}\}((?:(?!\{\{IF\s)[\s\S])*?))?\{\{\/IF\}\}/i;
      const match = pattern.exec(text);

      if (!match) {
        break; // No more conditionals
      }

      const fullMatch = match[0];

      // Parse all branches (IF, ELSEIF, ELSE)
      const result = this.parseAndEvaluateConditional(fullMatch, data);

      // Replace using index-based substring to handle edge cases
      text = text.substring(0, match.index) + result + text.substring(match.index + fullMatch.length);
    }

    if (iteration >= maxIterations) {
      throw new Error('Conditional processing hit iteration limit (' + maxIterations + ') - possible infinite loop or deeply nested conditionals');
    }

    return text;
  },

  parseAndEvaluateConditional: function(block, data) {
    // Extract all branches
    const branches = [];

    // Match IF branch
    let ifMatch = /\{\{IF\s+([^}]+)\}\}([\s\S]*?)(?=\{\{(?:ELSEIF|ELSE|\/IF))/i.exec(block);
    if (ifMatch) {
      branches.push({
        condition: ifMatch[1].trim(),
        content: ifMatch[2]
      });
    }

    // Match all ELSEIF branches
    const elseifPattern = /\{\{ELSEIF\s+([^}]+)\}\}([\s\S]*?)(?=\{\{(?:ELSEIF|ELSE|\/IF))/gi;
    let elseifMatch;
    while ((elseifMatch = elseifPattern.exec(block)) !== null) {
      branches.push({
        condition: elseifMatch[1].trim(),
        content: elseifMatch[2]
      });
    }

    // Match ELSE branch (no condition)
    const elseMatch = /\{\{ELSE\}\}([\s\S]*?)\{\{\/IF\}\}/i.exec(block);
    if (elseMatch) {
      branches.push({
        condition: null, // ELSE has no condition (always true)
        content: elseMatch[1]
      });
    }

    // Evaluate branches in order, return first true branch
    for (let i = 0; i < branches.length; i++) {
      const branch = branches[i];

      // ELSE branch (no condition) is always true
      if (branch.condition === null) {
        return branch.content;
      }

      // Evaluate condition
      try {
        const conditionMet = ExpressionEvaluator.evaluate(branch.condition, data);
        if (conditionMet) {
          return branch.content;
        }
      } catch (e) {
        throw new Error('Conditional evaluation failed for "' + branch.condition + '": ' + e.message);
      }
    }

    // No branch matched
    return '';
  },

  processParagraph: function(para, data) {
    let text = para.getText();

    // Quick check: skip if no conditionals
    if (text.indexOf('{{IF') === -1) {
      return false;
    }

    // Process the text
    const processedText = this.processText(text, data);

    if (processedText !== text) {
      para.clear();
      para.setText(processedText);
      return true;
    }

    return false;
  }
};
