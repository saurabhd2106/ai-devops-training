const express = require("express");
const demoRoutes = require("./routes/demoRoutes");

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use("/api", demoRoutes);

app.get("/", (req, res) => {
  res.json({ message: "sonarqube-node-demo is running" });
});

app.get("/health", (req, res) => {
  res.status(200).send("ok");
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
