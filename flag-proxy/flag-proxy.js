import express from "express";
import fetch from "node-fetch";

const app = express();
const { GITLAB_API_URL, GITLAB_ACCESS_TOKEN, PROJECT_ID } = process.env;

app.get("/flags", async (_req, res) => {
  try {
    const url = `${GITLAB_API_URL}/api/v4/projects/${PROJECT_ID}/feature_flags`;
    const r = await fetch(url, {
      headers: { Authorization: `Bearer ${GITLAB_ACCESS_TOKEN}` },
    });
    if (!r.ok) return res.status(r.status).json({ error: await r.text() });

    const data = await r.json();
    const out = {};
    data.forEach(f => (out[f.name] = !!f.active));
    res.json(out);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.listen(9000, () => console.log("Flag proxy running on :9000"));
