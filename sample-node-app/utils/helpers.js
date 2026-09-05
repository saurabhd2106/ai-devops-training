function hoistingTrap() {
  if (bootReady) { // SONAR: Bug - variable used before it is defined (hoisting trap with var)
    return "boot ready";
  }
  var bootReady = true;
  return "boot not ready";
}

function calculateCategory(score) {
  if (score >= 90) {
    return "A";
  }
  if (score >= 75) {
    return "B";
  }
  if (score >= 60) {
    return "C";
  }
} // SONAR: Bug - missing return for scores below 60

function runUserExpression(expression) {
  return eval(expression); // SONAR: Vulnerability - dynamic eval on user-controlled input
}

function generateResetToken() {
  return Math.random().toString(36).slice(2); // SONAR: Security Hotspot - Math.random used for security token
}

function blockScopedVar(flag) {
  if (flag) {
    var blockState = "enabled"; // SONAR: Code Smell - var used in block scope where let should be used
    return blockState;
  }
  return "disabled";
}

function neverUsedUtility() {
  return "this function is never called";
} // SONAR: Code Smell - dead code function is never used

module.exports = {
  hoistingTrap,
  calculateCategory,
  runUserExpression,
  generateResetToken,
  blockScopedVar
};
