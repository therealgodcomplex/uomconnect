-- ╔══════════════════════════════════════════════════════════════╗
-- ║  UoMConnect MVP — PostgreSQL Schema + Seed Data             ║
-- ║  Run once against your Render Postgres DB                   ║
-- ╚══════════════════════════════════════════════════════════════╝

-- ── EXTENSIONS ────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── DROP (safe re-run) ────────────────────────────────────────
DROP TABLE IF EXISTS forum_replies   CASCADE;
DROP TABLE IF EXISTS forum_posts     CASCADE;
DROP TABLE IF EXISTS complaints      CASCADE;
DROP TABLE IF EXISTS calendar_events CASCADE;
DROP TABLE IF EXISTS notices         CASCADE;

-- ══════════════════════════════════════════════════════════════
-- NOTICES
-- ══════════════════════════════════════════════════════════════
CREATE TABLE notices (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  title       TEXT        NOT NULL,
  body        TEXT        NOT NULL,
  category    TEXT        NOT NULL
                CHECK (category IN ('Exam','Admin','Timetable','Faculty','Registration','General')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_notices_category   ON notices (category);
CREATE INDEX idx_notices_created_at ON notices (created_at DESC);

-- ══════════════════════════════════════════════════════════════
-- CALENDAR EVENTS
-- ══════════════════════════════════════════════════════════════
CREATE TABLE calendar_events (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  title       TEXT        NOT NULL,
  event_date  DATE        NOT NULL,
  category    TEXT        NOT NULL
                CHECK (category IN ('Academic','Admin','Events','Opportunities')),
  description TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_cal_date     ON calendar_events (event_date);
CREATE INDEX idx_cal_category ON calendar_events (category);

-- ══════════════════════════════════════════════════════════════
-- FORUM POSTS
-- ══════════════════════════════════════════════════════════════
CREATE TABLE forum_posts (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  title       TEXT        NOT NULL CHECK (char_length(title) <= 200),
  body        TEXT        NOT NULL CHECK (char_length(body)  <= 5000),
  tag         TEXT        NOT NULL DEFAULT 'General'
                CHECK (tag IN ('Academic','Career','Study Group','General','Announcement')),
  author_name TEXT        NOT NULL DEFAULT 'Anonymous',
  author_role TEXT        NOT NULL DEFAULT 'Student'
                CHECK (author_role IN ('Student','Senior','Alumni','Staff','Admin')),
  is_pinned   BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_posts_tag        ON forum_posts (tag);
CREATE INDEX idx_posts_created_at ON forum_posts (created_at DESC);

-- ══════════════════════════════════════════════════════════════
-- FORUM REPLIES
-- ══════════════════════════════════════════════════════════════
CREATE TABLE forum_replies (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id     UUID        NOT NULL REFERENCES forum_posts(id) ON DELETE CASCADE,
  content     TEXT        NOT NULL CHECK (char_length(content) <= 2000),
  author_name TEXT        NOT NULL DEFAULT 'Anonymous',
  author_role TEXT        NOT NULL DEFAULT 'Student'
                CHECK (author_role IN ('Student','Senior','Alumni','Staff','Admin')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_replies_post_id ON forum_replies (post_id);

-- ══════════════════════════════════════════════════════════════
-- COMPLAINTS
-- ══════════════════════════════════════════════════════════════
CREATE TABLE complaints (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  ref_id         TEXT        NOT NULL UNIQUE,
  content        TEXT        NOT NULL CHECK (char_length(content) <= 3000),
  category       TEXT        NOT NULL DEFAULT 'General',
  status         TEXT        NOT NULL DEFAULT 'SUBMITTED'
                   CHECK (status IN ('SUBMITTED','IN_REVIEW','RESOLVED','CLOSED')),
  admin_response TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at    TIMESTAMPTZ
);
CREATE INDEX idx_complaints_status ON complaints (status);
CREATE INDEX idx_complaints_ref    ON complaints (ref_id);

-- ══════════════════════════════════════════════════════════════
-- AUTO-UPDATE updated_at TRIGGER
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_notices_updated    BEFORE UPDATE ON notices         FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_cal_updated        BEFORE UPDATE ON calendar_events FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_posts_updated      BEFORE UPDATE ON forum_posts     FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_complaints_updated BEFORE UPDATE ON complaints      FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ══════════════════════════════════════════════════════════════
-- SEED DATA — University of Mauritius
-- ══════════════════════════════════════════════════════════════

-- ── NOTICES ───────────────────────────────────────────────────
INSERT INTO notices (title, body, category) VALUES
  (
    'Mid-Semester Exam Schedule Released',
    'The mid-semester examination timetable for Semester 2 2025/26 is now available on the student portal. All examinations will be held in the main examination halls. Students are advised to check their individual timetables and report any clashes to the Examinations Office immediately.',
    'Exam'
  ),
  (
    'Course Registration Opens March 1',
    'Course registration for Semester 1 2026/27 will open on March 1, 2026 at 08:00. Students must log in to the student portal to register for their modules. Registration closes March 15. Late registration will incur an administrative fee.',
    'Admin'
  ),
  (
    'CS101 Lecture Rescheduled — LT-2 This Week',
    'Please note that the CS101 Introduction to Programming lecture has been moved from LT-1 to LT-2 for the week of 23–27 February 2026 due to maintenance works. This change affects Monday and Wednesday sessions only.',
    'Timetable'
  ),
  (
    'Guest Lecture: AI in Healthcare — Feb 28',
    'The Faculty of Engineering and Faculty of Science are pleased to announce a joint guest lecture on Artificial Intelligence in Healthcare. The lecture will be delivered by Dr. Priya Sewnarain from the Mauritius Institute of Technology. POWA Auditorium, 10:00–12:00. All students welcome.',
    'Faculty'
  ),
  (
    'Add/Drop Deadline: February 28, 2026',
    'The final date for students to add or drop modules for Semester 2 2025/26 is February 28, 2026. After this date, no module changes will be accepted. Students wishing to make changes must visit the Registrar''s Office with a completed Add/Drop form.',
    'Registration'
  ),
  (
    'Library Extended Hours — Exam Period',
    'The Swami Dayanand Library will operate extended hours from March 1 to March 20, 2026 in preparation for mid-semester examinations. New hours: Monday–Friday 07:00–22:00, Saturday 08:00–18:00, Sunday 10:00–16:00.',
    'General'
  );

-- ── CALENDAR EVENTS ───────────────────────────────────────────
INSERT INTO calendar_events (title, event_date, category, description) VALUES
  ('Data Structures Assignment 3 Due',     '2026-02-23', 'Academic',      'Submit via the student portal by 23:59'),
  ('Software Engineering Group Report Due','2026-02-24', 'Academic',      'Hard copy to Engineering Office + portal upload'),
  ('Add/Drop Module Deadline',             '2026-02-28', 'Admin',         'Last day to add or drop modules for Sem 2'),
  ('Guest Lecture: AI in Healthcare',      '2026-02-28', 'Events',        'POWA Auditorium 10:00–12:00'),
  ('Calculus II Problem Set Due',          '2026-02-26', 'Academic',      'Submit to Dr. Lutchmoodoo by 17:00'),
  ('Course Registration Opens',            '2026-03-01', 'Admin',         'Student portal — Sem 1 2026/27'),
  ('Mid-Semester Examinations Begin',      '2026-03-05', 'Academic',      'Check personal timetable for room allocations'),
  ('Mid-Semester Examinations End',        '2026-03-14', 'Academic',      'Results expected within 2 weeks'),
  ('UoM Career Fair 2026',                 '2026-03-10', 'Opportunities', 'Sports Complex — 09:00–16:00. 40+ employers'),
  ('Student Union Elections',              '2026-03-18', 'Events',        'Vote for your student representatives'),
  ('Semester 2 Lectures End',              '2026-04-24', 'Academic',      'Last day of formal teaching for Sem 2'),
  ('Final Examinations Begin',             '2026-05-04', 'Academic',      'Full exam timetable on student portal');

-- ── FORUM POSTS (seeded with realistic UoM content) ──────────
INSERT INTO forum_posts (title, body, tag, author_name, author_role, is_pinned) VALUES
  (
    'Tips for surviving Data Structures — from someone who failed it once',
    'Hey everyone. I failed DS in Year 1 and had to resit. Here''s what I wish I knew: (1) Don''t just memorise algorithms, understand WHY they work. (2) Practice on paper before coding. (3) The exam always has a BST question — know your rotations. (4) Form a study group — explaining to others is the best revision. Good luck to all sitting mids next week!',
    'Academic', 'Sarah M.', 'Senior', TRUE
  ),
  (
    'Internship at MCB — honest review and tips to get in',
    'I completed a 3-month internship at MCB Group last summer as a software intern. The application opens around November each year on their careers portal. Key tip: tailor your CV to the specific team. The technical interview was focused on SQL and basic algorithms. DM me if you want to see my CV format.',
    'Career', 'Raj K.', 'Alumni', FALSE
  ),
  (
    'Study group for Calculus II — anyone want to join?',
    'I''m organising a Calculus II study group ahead of mids. Planning to meet at the Library Group Study Room 2 on Tuesdays and Thursdays 14:00–16:00. We''ll go through past papers and problem sets together. WhatsApp me on +230 5XXX XXXX or reply here. Aiming for 4–6 people max.',
    'Study Group', 'Aisha T.', 'Student', FALSE
  ),
  (
    'How to structure the Software Engineering group report',
    'Our group was confused about the report structure so I asked Dr. Parsooramen. He confirmed: (1) Executive Summary (2) Requirements (3) Design — UML diagrams required (4) Implementation (5) Testing — must include test cases (6) Conclusion (7) References. IEEE format. Max 40 pages excluding appendices.',
    'Academic', 'Marc L.', 'Student', FALSE
  ),
  (
    'Canteen A vs Canteen B — which is actually better?',
    'Hot take: Canteen B near Science is criminally underrated. The rotis are fresher and the queue is always shorter. Canteen A is busier but has more variety. For a quick breakfast before 8am lecture, Canteen B wins every time. What does everyone else think?',
    'General', 'Priya S.', 'Student', FALSE
  ),
  (
    'UoM Career Fair — companies confirmed so far',
    'The Student Union just published the list of confirmed companies for the Career Fair on March 10. Highlights: MCB Group, Accenture Mauritius, Rogers Capital, Air Mauritius, Mauritius Telecom, Ceridian, IBM, and about 15 SMEs. Bring printed CVs — some companies do on-the-spot interviews!',
    'Career', 'Student Union', 'Admin', TRUE
  );

-- ── FORUM REPLIES ─────────────────────────────────────────────
-- (Get post IDs dynamically for replies)
INSERT INTO forum_replies (post_id, content, author_name, author_role)
SELECT id, 'This is exactly what I needed. The BST rotations always trip me up. Do you have any good YouTube channels for DS revision?', 'Kevin A.', 'Student'
FROM forum_posts WHERE title LIKE 'Tips for surviving Data Structures%';

INSERT INTO forum_replies (post_id, content, author_name, author_role)
SELECT id, 'I''d recommend Abdul Bari on YouTube — best DS explanations I''ve found. Also MIT OpenCourseWare 6.006.', 'Sarah M.', 'Senior'
FROM forum_posts WHERE title LIKE 'Tips for surviving Data Structures%';

INSERT INTO forum_replies (post_id, content, author_name, author_role)
SELECT id, 'I''m interested in the study group! I''m free both Tuesdays and Thursdays. Will WhatsApp you.', 'Nadia F.', 'Student'
FROM forum_posts WHERE title LIKE 'Study group for Calculus II%';

INSERT INTO forum_replies (post_id, content, author_name, author_role)
SELECT id, 'Thanks for this! Quick question — does the report need a Gantt chart showing project timeline?', 'Omar D.', 'Student'
FROM forum_posts WHERE title LIKE 'How to structure the Software Engineering%';

INSERT INTO forum_replies (post_id, content, author_name, author_role)
SELECT id, 'Dr. Parsooramen said it''s optional but recommended — shows project management awareness.', 'Marc L.', 'Student'
FROM forum_posts WHERE title LIKE 'How to structure the Software Engineering%';

-- ── SAMPLE COMPLAINT ──────────────────────────────────────────
INSERT INTO complaints (ref_id, content, category, status) VALUES
  ('C-SEED001', 'The WiFi signal in Block C labs is extremely weak, particularly in rooms C201 and C203. This affects our ability to access online resources during practical sessions. The issue has been ongoing for approximately 3 weeks.', 'Infrastructure', 'RESOLVED'),
  ('C-SEED002', 'The canteen regularly runs out of vegetarian options before 12:30, leaving vegetarian students with very limited choices. More variety and better stock management would be appreciated.', 'Facilities', 'IN_REVIEW');

UPDATE complaints SET admin_response = 'WiFi access points in Block C have been upgraded as of February 15. Please report if the issue persists.', resolved_at = NOW()
WHERE ref_id = 'C-SEED001';