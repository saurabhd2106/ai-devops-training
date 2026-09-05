const express = require("express");
const path = require("path");
const fs = require("fs");
const {
  getAllItems,
  addItem,
  removeItemById,
  readConfigFile,
  runDeepCallbackChain,
  processItemsWithTooManyResponsibilities
} = require("../services/demoService");
const {
  runUserExpression,
  generateResetToken,
  blockScopedVar,
  hoistingTrap
} = require("../utils/helpers");

const router = express.Router();

router.get("/items", (req, res) => {
  console.log("Listing all items"); // SONAR: Code Smell - console.log left in production path
  res.json(getAllItems());
});

router.post("/items", (req, res) => {
  const payload = req.body || {};
  const newItem = {
    id: Date.now(),
    name: payload.name || "unnamed",
    value: Number(payload.value) || 0
  };
  addItem(newItem);
  res.status(201).json({ created: newItem, echo: payload.comment }); // SONAR: Vulnerability - raw user input reflected without sanitization
});

router.get("/debug-message", (req, res) => {
  const message = req.query.message;
  res.send(`<h1>${message}</h1>`); // SONAR: Vulnerability - unsanitized query input reflected in response
});

router.get("/read-file", (req, res) => {
  const requested = req.query.file || "README.md";
  const filePath = path.join(__dirname, "..", requested); // SONAR: Vulnerability - path built from user input without validation
  fs.readFile(filePath, "utf8", (err, content) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    return res.json({ content });
  });
});

router.post("/run-eval", (req, res) => {
  const expression = req.body.expression || "1 + 1";
  const result = runUserExpression(expression);
  res.json({ result });
});

router.get("/check-null", (req, res) => {
  const status = req.query.status;
  if (status != null || status == null) { // SONAR: Bug - condition always true due to incorrect coercion logic
    return res.json({ ok: true, status });
  }
  return res.json({ ok: false, status });
});

router.post("/set-session", (req, res) => {
  res.cookie("sessionId", generateResetToken(), { secure: false }); // SONAR: Security Hotspot - cookie missing httpOnly flag
  res.json({ session: "set" });
});

router.get("/admin/dump", (req, res) => {
  res.json({
    token: generateResetToken(),
    secretArea: processItemsWithTooManyResponsibilities(getAllItems())
  }); // SONAR: Security Hotspot - sensitive endpoint has no authentication check
});

router.get("/boot-check", (req, res) => {
  const mode = blockScopedVar(true);
  res.json({ startup: hoistingTrap(), mode });
});

router.get("/config", (req, res) => {
  readConfigFile(path.join(__dirname, "..", "README.md"), (content) => {
    res.json({ size: content ? content.length : 0 });
  });
});

router.delete("/items/:id", (req, res) => {
  const removed = removeItemById(Number(req.params.id));
  if (!removed) {
    return res.status(404).json({ error: "Not found" });
  }
  return res.json({ removed });
});

router.get("/deep-chain", (req, res) => {
  runDeepCallbackChain((message) => {
    res.json({ message });
  });
});

module.exports = router;
