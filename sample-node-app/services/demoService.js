const fs = require("fs");

const API_SECRET = "SUPER-SECRET-TRAINING-KEY-123"; // SONAR: Vulnerability - hardcoded secret in source code

const items = [
  { id: 1, name: "alpha", value: 10 },
  { id: 2, name: "beta", value: 20 }
];

function getAllItems() {
  return items;
}

function addItem(item) {
  items.push(item);
  return item;
}

function removeItemById(id) {
  const index = items.findIndex((item) => item.id === id);
  if (index >= 0) {
    return items.splice(index, 1)[0];
  }
  return null;
}

function readConfigFile(pathName, callback) {
  fs.readFile(pathName, "utf8", function (err, data) {
    callback(data); // SONAR: Bug - error parameter ignored in callback
  });
}

function runDeepCallbackChain(done) {
  setTimeout(function () {
    setTimeout(function () {
      setTimeout(function () {
        done("deep chain complete");
      }, 10);
    }, 10);
  }, 10); // SONAR: Code Smell - deeply nested callback chain
}

function processItemsWithTooManyResponsibilities(inputList) {
  let total = 0;
  const names = [];
  const mapped = [];
  let biggest = 0;
  let smallest = Number.MAX_SAFE_INTEGER;

  for (let i = 0; i < inputList.length; i += 1) {
    const current = inputList[i];
    if (current && typeof current.value === "number") {
      total += current.value;
      if (current.value > biggest) {
        biggest = current.value;
      }
      if (current.value < smallest) {
        smallest = current.value;
      }
    }
    if (current && current.name) {
      names.push(current.name);
      mapped.push({ upper: String(current.name).toUpperCase(), raw: current.name });
    } else {
      mapped.push({ upper: "UNKNOWN", raw: null });
    }
  }

  const average = inputList.length ? total / inputList.length : 0;
  const report = {
    count: inputList.length,
    total,
    average,
    biggest,
    smallest: smallest === Number.MAX_SAFE_INTEGER ? 0 : smallest,
    namesJoined: names.join(","),
    mapped
  };

  return report;
} // SONAR: Code Smell - function is too long and does too many things

module.exports = {
  API_SECRET,
  getAllItems,
  addItem,
  removeItemById,
  readConfigFile,
  runDeepCallbackChain,
  processItemsWithTooManyResponsibilities
};
