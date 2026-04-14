require("dotenv").config();
const express = require("express");
const cors = require("cors");
const mongoose = require("mongoose");

const app = express();
app.use(cors());
app.use(express.json());

const BEARER_TOKEN = process.env.BEARER_TOKEN;
const MONGODB_URI = process.env.MONGODB_URI;
const DB_NAME = process.env.MONGODB_DB;
const PORT = process.env.PORT || 30001;

// Connect to MongoDB
mongoose.connect(MONGODB_URI, { dbName: DB_NAME })
  .then(() => console.log("Connected to MongoDB"))
  .catch((err) => { console.error("MongoDB connection error:", err); process.exit(1); });

// Schema
const healthSchema = new mongoose.Schema({
  date: String,
  heartRate: Number,
  steps: Number,
  calories: Number,
  distanceKm: Number,
  sleepHours: Number,
  workouts: Array,
  receivedAt: String,
});
const HealthData = mongoose.model("HealthData", healthSchema);

// Middleware: check bearer
function auth(req, res, next) {
  const token = req.headers.authorization?.replace("Bearer ", "");
  if (token !== BEARER_TOKEN) {
    return res.status(401).json({ error: "Invalid token" });
  }
  next();
}

// POST /api/send-data — iPhone app sends health data here
app.post("/api/send-data", auth, async (req, res) => {
  try {
    const entry = new HealthData({ ...req.body, receivedAt: new Date().toISOString() });
    await entry.save();
    console.log("Health data saved:", entry);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/get-data — Fetch latest stored health data
app.get("/api/get-data", auth, async (req, res) => {
  try {
    const latest = await HealthData.findOne().sort({ receivedAt: -1 });
    if (!latest) return res.json({ message: "No data yet" });
    res.json(latest);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, () => {
  console.log(`health-data-pull API running on http://localhost:${PORT}`);
});
