const assert = require('assert');
const fs = require('fs');
const path = require('path');

describe('Database Rules Syntax & Policy Compilation Tests', () => {
  const transitionalRulesPath = path.join(__dirname, '../../database.transitional.rules.json');
  const finalRulesPath = path.join(__dirname, '../../database.rules.json');
  const firebaseJsonPath = path.join(__dirname, '../../firebase.json');
  const firebaseTransitionalJsonPath = path.join(__dirname, '../../firebase.transitional.json');

  it('1. Verify configuration files reference intended rules files', () => {
    const firebaseJson = JSON.parse(fs.readFileSync(firebaseJsonPath, 'utf8'));
    const firebaseTransitionalJson = JSON.parse(fs.readFileSync(firebaseTransitionalJsonPath, 'utf8'));

    assert.strictEqual(firebaseJson.database.rules, 'database.rules.json');
    assert.strictEqual(firebaseTransitionalJson.database.rules, 'database.transitional.rules.json');
  });

  it('2. Verify Transitional Rules syntax and permission structure', () => {
    const rulesText = fs.readFileSync(transitionalRulesPath, 'utf8');
    const rulesObj = JSON.parse(rulesText);
    assert(rulesObj.rules);

    // Transitional rules check
    const userConvRule = rulesObj.rules.userConversations['$userId'];
    assert.strictEqual(userConvRule['.read'], 'auth != null && auth.uid == $userId');
    assert.strictEqual(userConvRule['.write'], false);

    // Legacy chat write access preserved in transitional phase
    assert.strictEqual(rulesObj.rules.conversations['.write'], 'auth != null');
  });

  it('3. Verify Final Rules syntax and permission structure', () => {
    const rulesText = fs.readFileSync(finalRulesPath, 'utf8');
    const rulesObj = JSON.parse(rulesText);
    assert(rulesObj.rules);

    // Final rules check
    const userConvRule = rulesObj.rules.userConversations['$userId'];
    assert.strictEqual(userConvRule['.read'], 'auth != null && auth.uid == $userId');
    assert.strictEqual(userConvRule['.write'], false);

    // Restrictive conversations check (Client writes disabled)
    const convChildRule = rulesObj.rules.conversations['$conversationId'];
    assert.strictEqual(convChildRule['.write'], false);
    assert(convChildRule['.read'].includes('participants'));
  });
});
