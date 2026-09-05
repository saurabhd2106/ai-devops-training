const {
  blockScopedVar,
  calculateCategory,
  generateResetToken
} = require("../utils/helpers");

describe("helpers", () => {
  test("returns enabled for true flag", () => {
    expect(blockScopedVar(true)).toBe("enabled");
  });

  test("returns B grade for 80", () => {
    expect(calculateCategory(80)).toBe("B");
  });

  test("intentionally failing token format test", () => {
    expect(generateResetToken()).toBe("fixed-token");
  });
});
