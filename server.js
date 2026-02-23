// ╔══════════════════════════════════════════════════════════════╗
// ║  UoMConnect — MVP Backend                                   ║
// ║  Express + PostgreSQL (pg) + Socket.IO                      ║
// ║  No auth — deploy straight to Render                        ║
// ╚══════════════════════════════════════════════════════════════╝
// npm install express pg cors helmet express-rate-limit socket.io morgan

import express       from "express";
import cors          from "cors";
import helmet        from "helmet";
import rateLimit     from "express-rate-limit";
import morgan        from "morgan";
import { createServer } from "http";
import { Server as IO } from "socket.io";
import pg            from "pg";
import path          from "path";
import { fileURLToPath } from "url";
import "dotenv/config";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app  = express();
const http = createServer(app);
const io   = new IO(http, {
  cors: { origin: "*", methods: ["GET","POST","PATCH","DELETE"] }
});

// ── DB POOL ────────────────────────────────────────────────────
const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === "production"
    ? { rejectUnauthorized: false }
    : false,
});

// ── MIDDLEWARE ─────────────────────────────────────────────────
app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors());
app.use(express.json());
app.use(morgan("dev"));

const limiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 300 });
app.use("/api", limiter);

// Serve frontend static files from /public
app.use(express.static(path.join(__dirname, "public")));

// ── HEALTH ─────────────────────────────────────────────────────
app.get("/api/health", async (_, res) => {
  try {
    await pool.query("SELECT 1");
    res.json({ status: "ok", db: "connected", ts: new Date().toISOString() });
  } catch (e) {
    res.status(500).json({ status: "error", message: e.message });
  }
});

// ══════════════════════════════════════════════════════════════
// ①  NOTICES
// ══════════════════════════════════════════════════════════════
app.get("/api/notices", async (req, res) => {
  const { category, page = 1, limit = 20 } = req.query;
  const offset = (Number(page) - 1) * Number(limit);
  try {
    const { rows } = await pool.query(
      `SELECT * FROM notices
       WHERE ($1::text IS NULL OR category = $1)
       ORDER BY created_at DESC
       LIMIT $2 OFFSET $3`,
      [category || null, Number(limit), offset]
    );
    const { rows: [{ count }] } = await pool.query(
      `SELECT COUNT(*) FROM notices WHERE ($1::text IS NULL OR category = $1)`,
      [category || null]
    );
    res.json({ data: rows, total: Number(count), page: Number(page) });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get("/api/notices/:id", async (req, res) => {
  const { rows } = await pool.query("SELECT * FROM notices WHERE id=$1", [req.params.id]);
  if (!rows[0]) return res.status(404).json({ error: "Not found" });
  res.json(rows[0]);
});

// Admin-key protected (simple header check, no full auth)
app.post("/api/notices", adminGuard, async (req, res) => {
  const { title, body, category } = req.body;
  if (!title || !body || !category)
    return res.status(400).json({ error: "title, body, category required" });
  const { rows } = await pool.query(
    `INSERT INTO notices (title, body, category) VALUES ($1,$2,$3) RETURNING *`,
    [title, body, category]
  );
  io.emit("notice:new", rows[0]);
  res.status(201).json(rows[0]);
});

app.patch("/api/notices/:id", adminGuard, async (req, res) => {
  const { title, body, category } = req.body;
  const { rows } = await pool.query(
    `UPDATE notices SET title=COALESCE($1,title), body=COALESCE($2,body),
     category=COALESCE($3,category), updated_at=NOW()
     WHERE id=$4 RETURNING *`,
    [title, body, category, req.params.id]
  );
  if (!rows[0]) return res.status(404).json({ error: "Not found" });
  io.emit("notice:updated", rows[0]);
  res.json(rows[0]);
});

app.delete("/api/notices/:id", adminGuard, async (req, res) => {
  await pool.query("DELETE FROM notices WHERE id=$1", [req.params.id]);
  io.emit("notice:deleted", { id: req.params.id });
  res.json({ ok: true });
});

// ══════════════════════════════════════════════════════════════
// ②  CALENDAR EVENTS
// ══════════════════════════════════════════════════════════════
app.get("/api/calendar", async (req, res) => {
  const { month, year, category } = req.query;
  if (!month || !year) return res.status(400).json({ error: "month and year required" });
  try {
    const start = `${year}-${String(month).padStart(2,"0")}-01`;
    const end   = `${year}-${String(month).padStart(2,"0")}-31`;
    const { rows } = await pool.query(
      `SELECT * FROM calendar_events
       WHERE event_date BETWEEN $1 AND $2
         AND ($3::text IS NULL OR category = $3)
       ORDER BY event_date ASC`,
      [start, end, category || null]
    );
    res.json(rows);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.post("/api/calendar", adminGuard, async (req, res) => {
  const { title, event_date, category, description } = req.body;
  if (!title || !event_date || !category)
    return res.status(400).json({ error: "title, event_date, category required" });
  const { rows } = await pool.query(
    `INSERT INTO calendar_events (title, event_date, category, description)
     VALUES ($1,$2,$3,$4) RETURNING *`,
    [title, event_date, category, description || null]
  );
  io.emit("calendar:new", rows[0]);
  res.status(201).json(rows[0]);
});

app.patch("/api/calendar/:id", adminGuard, async (req, res) => {
  const { title, event_date, category, description } = req.body;
  const { rows } = await pool.query(
    `UPDATE calendar_events
     SET title=COALESCE($1,title), event_date=COALESCE($2,event_date),
         category=COALESCE($3,category), description=COALESCE($4,description),
         updated_at=NOW()
     WHERE id=$5 RETURNING *`,
    [title, event_date, category, description, req.params.id]
  );
  if (!rows[0]) return res.status(404).json({ error: "Not found" });
  io.emit("calendar:updated", rows[0]);
  res.json(rows[0]);
});

app.delete("/api/calendar/:id", adminGuard, async (req, res) => {
  await pool.query("DELETE FROM calendar_events WHERE id=$1", [req.params.id]);
  io.emit("calendar:deleted", { id: req.params.id });
  res.json({ ok: true });
});

// ══════════════════════════════════════════════════════════════
// ③  FORUM POSTS & REPLIES
// ══════════════════════════════════════════════════════════════
app.get("/api/forums", async (req, res) => {
  const { tag, page = 1, limit = 20 } = req.query;
  const offset = (Number(page) - 1) * Number(limit);
  try {
    const { rows } = await pool.query(
      `SELECT p.*,
         COUNT(r.id)::int AS reply_count
       FROM forum_posts p
       LEFT JOIN forum_replies r ON r.post_id = p.id
       WHERE ($1::text IS NULL OR p.tag = $1)
       GROUP BY p.id
       ORDER BY p.created_at DESC
       LIMIT $2 OFFSET $3`,
      [tag || null, Number(limit), offset]
    );
    res.json(rows);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get("/api/forums/:id", async (req, res) => {
  const { rows } = await pool.query(
    "SELECT * FROM forum_posts WHERE id=$1", [req.params.id]
  );
  if (!rows[0]) return res.status(404).json({ error: "Not found" });
  res.json(rows[0]);
});

app.post("/api/forums", async (req, res) => {
  const { title, body, tag, author_name, author_role } = req.body;
  if (!title || !body)
    return res.status(400).json({ error: "title and body required" });

  // Basic profanity / length guard
  if (title.length > 200 || body.length > 5000)
    return res.status(400).json({ error: "Content too long" });

  const { rows } = await pool.query(
    `INSERT INTO forum_posts (title, body, tag, author_name, author_role)
     VALUES ($1,$2,$3,$4,$5) RETURNING *`,
    [
      title, body,
      tag         || "General",
      sanitize(author_name) || "Anonymous",
      author_role || "Student",
    ]
  );
  const post = { ...rows[0], reply_count: 0 };
  io.emit("forum:new", post);
  res.status(201).json(post);
});

app.delete("/api/forums/:id", adminGuard, async (req, res) => {
  await pool.query("DELETE FROM forum_posts WHERE id=$1", [req.params.id]);
  io.emit("forum:deleted", { id: req.params.id });
  res.json({ ok: true });
});

// Replies
app.get("/api/forums/:id/replies", async (req, res) => {
  const { rows } = await pool.query(
    `SELECT * FROM forum_replies WHERE post_id=$1 ORDER BY created_at ASC`,
    [req.params.id]
  );
  res.json(rows);
});

app.post("/api/forums/:id/replies", async (req, res) => {
  const { content, author_name, author_role } = req.body;
  if (!content) return res.status(400).json({ error: "content required" });
  if (content.length > 2000) return res.status(400).json({ error: "Reply too long" });

  // Check post exists
  const { rows: [post] } = await pool.query(
    "SELECT id FROM forum_posts WHERE id=$1", [req.params.id]
  );
  if (!post) return res.status(404).json({ error: "Post not found" });

  const { rows } = await pool.query(
    `INSERT INTO forum_replies (post_id, content, author_name, author_role)
     VALUES ($1,$2,$3,$4) RETURNING *`,
    [
      req.params.id,
      content,
      sanitize(author_name) || "Anonymous",
      author_role || "Student",
    ]
  );
  io.to(`forum:${req.params.id}`).emit("reply:new", rows[0]);
  // Bump reply count
  io.emit("forum:replyCount", { post_id: req.params.id });
  res.status(201).json(rows[0]);
});

app.delete("/api/forums/:postId/replies/:id", adminGuard, async (req, res) => {
  await pool.query("DELETE FROM forum_replies WHERE id=$1", [req.params.id]);
  res.json({ ok: true });
});

// ══════════════════════════════════════════════════════════════
// ④  COMPLAINTS (anonymous)
// ══════════════════════════════════════════════════════════════
app.post("/api/complaints", async (req, res) => {
  const { content, category } = req.body;
  if (!content) return res.status(400).json({ error: "content required" });
  if (content.length > 3000) return res.status(400).json({ error: "Too long" });

  const ref_id = "C-" + Date.now().toString(36).toUpperCase();
  try {
    const { rows } = await pool.query(
      `INSERT INTO complaints (ref_id, content, category, status)
       VALUES ($1,$2,$3,'SUBMITTED') RETURNING ref_id, status, created_at`,
      [ref_id, content, category || "General"]
    );
    io.to("admins").emit("complaint:new", rows[0]);
    res.status(201).json(rows[0]);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// Public — check status by ref ID
app.get("/api/complaints/:ref_id", async (req, res) => {
  const { rows } = await pool.query(
    `SELECT ref_id, category, status, admin_response, created_at, resolved_at
     FROM complaints WHERE ref_id=$1`,
    [req.params.ref_id.toUpperCase()]
  );
  if (!rows[0]) return res.status(404).json({ error: "Not found" });
  res.json(rows[0]);
});

// Admin — list all
app.get("/api/complaints", adminGuard, async (req, res) => {
  const { status } = req.query;
  const { rows } = await pool.query(
    `SELECT ref_id, category, status, LEFT(content,80) AS preview,
            admin_response, created_at, resolved_at
     FROM complaints
     WHERE ($1::text IS NULL OR status=$1)
     ORDER BY created_at DESC`,
    [status || null]
  );
  res.json(rows);
});

// Admin — update status
app.patch("/api/complaints/:ref_id", adminGuard, async (req, res) => {
  const { status, admin_response } = req.body;
  const { rows } = await pool.query(
    `UPDATE complaints
     SET status=COALESCE($1,status),
         admin_response=COALESCE($2,admin_response),
         resolved_at=CASE WHEN $1='RESOLVED' THEN NOW() ELSE resolved_at END,
         updated_at=NOW()
     WHERE ref_id=$3
     RETURNING ref_id, status, admin_response`,
    [status, admin_response, req.params.ref_id.toUpperCase()]
  );
  if (!rows[0]) return res.status(404).json({ error: "Not found" });
  io.emit("complaint:updated", rows[0]);
  res.json(rows[0]);
});

// ══════════════════════════════════════════════════════════════
// SOCKET.IO
// ══════════════════════════════════════════════════════════════
io.on("connection", socket => {
  // Join forum room for live replies
  socket.on("forum:join",  id => socket.join(`forum:${id}`));
  socket.on("forum:leave", id => socket.leave(`forum:${id}`));
  // Admin room (protected by key)
  socket.on("admin:join", key => {
    if (key === process.env.ADMIN_KEY) socket.join("admins");
  });
  socket.on("forum:typing", ({ postId, name }) => {
    socket.to(`forum:${postId}`).emit("forum:typing", { name });
  });
});

// ══════════════════════════════════════════════════════════════
// SPA FALLBACK — serve frontend for all non-API routes
// ══════════════════════════════════════════════════════════════
app.get("*", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

// ── HELPERS ────────────────────────────────────────────────────
function adminGuard(req, res, next) {
  const key = req.headers["x-admin-key"] || req.query.admin_key;
  if (!key || key !== process.env.ADMIN_KEY)
    return res.status(403).json({ error: "Forbidden — invalid admin key" });
  next();
}

function sanitize(str) {
  if (!str) return str;
  return String(str)
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .slice(0, 80);
}

// ── START ──────────────────────────────────────────────────────
const PORT = process.env.PORT || 4000;
http.listen(PORT, () => {
  console.log(`✅ UoMConnect MVP running on :${PORT}`);
  console.log(`   NODE_ENV  : ${process.env.NODE_ENV || "development"}`);
  console.log(`   DB        : ${process.env.DATABASE_URL ? "connected" : "⚠ DATABASE_URL missing"}`);
  console.log(`   Admin key : ${process.env.ADMIN_KEY ? "set ✓" : "⚠ NOT SET"}`);
});