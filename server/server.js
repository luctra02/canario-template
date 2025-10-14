import express from "express";
import fetch from "node-fetch";

const app = express();
const { GITLAB_ACCESS_TOKEN, PROJECT_ID } = process.env;

// Serve static files
app.use(express.static("site"));

// Feature flag route
app.get("/flags", async (_req, res) => {
  try {
    const url = `https://gitlab.cs.oslomet.no/api/v4/projects/${PROJECT_ID}/feature_flags`;
    const r = await fetch(url, { headers: { Authorization: `Bearer ${GITLAB_ACCESS_TOKEN}` } });
    if (!r.ok) return res.status(r.status).json({ error: await r.text() });

    const data = await r.json();
    const out = {};
    data.forEach(f => (out[f.name] = !!f.active));
    res.json(out);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get("/health", (_req, res) => res.sendStatus(200));


app.listen(8080, () => console.log("Web + Flag proxy running on :8080"));
