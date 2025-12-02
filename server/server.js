import express from "express";
import fetch from "node-fetch";

const app = express();
const { GITLAB_ACCESS_TOKEN, PROJECT_ID } = process.env;

// Validate required environment variables on startup
if (!PROJECT_ID || !GITLAB_ACCESS_TOKEN) {
    console.error(
        "[ERROR] Missing required environment variables: PROJECT_ID, GITLAB_ACCESS_TOKEN"
    );
    process.exit(1);
}

console.log(`[INFO] Server starting for project ${PROJECT_ID}`);
console.log(`[INFO] Feature flag endpoint will fetch from GitLab API`);

// Serve static files
app.use(express.static("site"));

// Feature flag route
app.get("/flags", async (_req, res) => {
    try {
        const url = `https://gitlab.cs.oslomet.no/api/v4/projects/${PROJECT_ID}/feature_flags`;
        const r = await fetch(url, {
            headers: { Authorization: `Bearer ${GITLAB_ACCESS_TOKEN}` },
        });

        if (!r.ok) {
            console.error(
                `[ERROR] GitLab API returned ${r.status}: ${await r.text()}`
            );
            return res
                .status(r.status)
                .json({ error: `Failed to fetch feature flags: ${r.status}` });
        }

        const data = await r.json();
        const out = {};
        data.forEach((f) => (out[f.name] = !!f.active));

        console.log(
            `[INFO] Feature flags fetched: ${
                Object.keys(out).length
            } flags found`
        );
        res.json(out);
    } catch (e) {
        console.error(`[ERROR] Feature flag fetch failed: ${e.message}`);
        res.status(500).json({ error: e.message });
    }
});

app.listen(8080, () => console.log("Web + Flag proxy running on :8080"));
