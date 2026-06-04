const fs = require("fs");
const path = require("path");

const OUT_DIR = __dirname;
const W = 3300;
const H = 2550;

function esc(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function tableHeight(fields) {
  return 74 + fields.length * 34 + 18;
}

function tableSvg(entity) {
  const {
    id,
    x,
    y,
    w,
    title,
    subtitle,
    fields,
    header = "#1f6f78",
    accent = "#d5eef0",
  } = entity;
  const h = entity.h || tableHeight(fields);
  const rows = fields.map((field, index) => {
    const ry = y + 72 + index * 34;
    const isKey = /\((PK|FK)\)/.test(field) || field.includes("(subcollection)");
    const fill = isKey ? accent : "#ffffff";
    const weight = isKey ? "700" : "500";
    return [
      `<rect x="${x}" y="${ry}" width="${w}" height="34" fill="${fill}" stroke="#c7d1d8" stroke-width="1"/>`,
      `<text x="${x + 22}" y="${ry + 23}" class="field" font-weight="${weight}">${esc(field)}</text>`,
    ].join("\n");
  }).join("\n");

  return `
  <g id="${id}">
    <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="18" fill="#ffffff" stroke="#25343b" stroke-width="3"/>
    <rect x="${x}" y="${y}" width="${w}" height="72" rx="18" fill="${header}" stroke="#25343b" stroke-width="3"/>
    <path d="M ${x} ${y + 52} L ${x} ${y + 72} L ${x + w} ${y + 72} L ${x + w} ${y + 52}" fill="${header}" stroke="none"/>
    <text x="${x + w / 2}" y="${y + 31}" class="title" text-anchor="middle">${esc(title)}</text>
    <text x="${x + w / 2}" y="${y + 56}" class="subtitle" text-anchor="middle">${esc(subtitle || "Firestore collection")}</text>
${rows}
  </g>`;
}

function edgeSvg(edge) {
  const {
    from,
    to,
    label,
    c1,
    c2,
    color = "#64717a",
    dashed = false,
    labelX,
    labelY,
    width = 3,
  } = edge;
  const dash = dashed ? " stroke-dasharray=\"12 9\"" : "";
  const d = `M ${from[0]} ${from[1]} C ${c1[0]} ${c1[1]}, ${c2[0]} ${c2[1]}, ${to[0]} ${to[1]}`;
  const labelText = label ? `
    <g>
      <rect x="${labelX - 118}" y="${labelY - 18}" width="236" height="36" rx="16" fill="#ffffff" stroke="${color}" stroke-width="2"/>
      <text x="${labelX}" y="${labelY + 7}" class="edgeLabel" text-anchor="middle">${esc(label)}</text>
    </g>` : "";
  return `
    <path d="${d}" fill="none" stroke="${color}" stroke-width="${width}"${dash} marker-end="url(#arrow)"/>
${labelText}`;
}

function noteSvg(x, y, w, lines, color = "#f7fbff") {
  const h = 42 + lines.length * 28;
  const text = lines.map((line, index) =>
    `<text x="${x + 24}" y="${y + 42 + index * 28}" class="note">${esc(line)}</text>`
  ).join("\n");
  return `
  <g>
    <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="18" fill="${color}" stroke="#9aa8b2" stroke-width="2"/>
${text}
  </g>`;
}

function svgPage(title, subtitle, entities, edges, notes = []) {
  const tables = entities.map(tableSvg).join("\n");
  const links = edges.map(edgeSvg).join("\n");
  const noteBlocks = notes.join("\n");
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="11in" height="8.5in" viewBox="0 0 ${W} ${H}">
  <defs>
    <marker id="arrow" markerWidth="16" markerHeight="16" refX="13" refY="5" orient="auto" markerUnits="strokeWidth">
      <path d="M 0 0 L 13 5 L 0 10 z" fill="#64717a"/>
    </marker>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="8" stdDeviation="8" flood-color="#18242c" flood-opacity="0.12"/>
    </filter>
  </defs>
  <style>
    .pageTitle { font: 700 52px Arial, Helvetica, sans-serif; fill: #1f2933; }
    .pageSubtitle { font: 500 25px Arial, Helvetica, sans-serif; fill: #52616b; }
    .title { font: 700 25px Arial, Helvetica, sans-serif; fill: #ffffff; }
    .subtitle { font: 600 15px Arial, Helvetica, sans-serif; fill: #ecfeff; letter-spacing: 0; }
    .field { font: 18px Arial, Helvetica, sans-serif; fill: #24343d; }
    .edgeLabel { font: 700 18px Arial, Helvetica, sans-serif; fill: #34444d; }
    .note { font: 20px Arial, Helvetica, sans-serif; fill: #33444e; }
    g[id] { filter: none; }
  </style>
  <rect width="${W}" height="${H}" fill="#f7f9fb"/>
  <rect x="50" y="50" width="${W - 100}" height="${H - 100}" rx="34" fill="#ffffff" stroke="#d7e0e7" stroke-width="2"/>
  <text x="${W / 2}" y="112" class="pageTitle" text-anchor="middle">${esc(title)}</text>
  <text x="${W / 2}" y="154" class="pageSubtitle" text-anchor="middle">${esc(subtitle)}</text>
  <g id="edges">
${links}
  </g>
  <g id="entities">
${tables}
  </g>
${noteBlocks}
</svg>`;
}

const coreEntities = [
  {
    id: "auth", x: 100, y: 210, w: 380, h: 250,
    title: "Firebase Auth", subtitle: "identity provider",
    header: "#5661b3", accent: "#eceffd",
    fields: ["uid (PK)", "email", "provider"],
  },
  {
    id: "users", x: 610, y: 190, w: 545,
    title: "users", subtitle: "profiles and roles",
    header: "#1f6f78", accent: "#d7f0f2",
    fields: [
      "userId / uid (PK)", "email", "fullName", "phoneNumber", "dateOfBirth",
      "bloodType", "allergies", "role", "studentId", "staffId", "isActive",
      "language", "notificationSettings", "googleEmail", "adminPermissions",
    ],
  },
  {
    id: "doctors", x: 1465, y: 190, w: 540,
    title: "doctors", subtitle: "doctor profiles",
    header: "#2f855a", accent: "#ddf3e5",
    fields: [
      "doctorId (PK)", "userId (FK)", "name", "email", "photoUrl", "department",
      "specialization", "bio", "experienceYears", "qualifications", "isAvailable",
      "isActive", "weeklySchedule", "dailyNotificationTime",
    ],
  },
  {
    id: "departments", x: 2375, y: 190, w: 545,
    title: "departments", subtitle: "clinic areas",
    header: "#b7791f", accent: "#fff2d6",
    fields: [
      "key (PK)", "name", "description", "iconName", "colorHex", "workingHours",
      "isActive", "doctorCount",
    ],
  },
  {
    id: "user_tokens", x: 100, y: 860, w: 430,
    title: "user_tokens", subtitle: "push devices",
    header: "#5661b3", accent: "#eceffd",
    fields: [
      "userId (FK)", "tokens (subcollection)", "token", "tokenHash", "deviceInfo",
      "timezone", "updatedAt",
    ],
  },
  {
    id: "notifications", x: 650, y: 920, w: 555,
    title: "notifications", subtitle: "messages and reminders",
    header: "#805ad5", accent: "#efe8ff",
    fields: [
      "notificationId (PK)", "userId (FK)", "title", "body", "type", "data",
      "isRead", "createdAt", "appointmentId (FK)", "scheduledFor", "reminderType",
      "isDelivered",
    ],
  },
  {
    id: "appointments", x: 1415, y: 900, w: 620,
    title: "appointments", subtitle: "booking records",
    header: "#c05621", accent: "#ffeadb",
    fields: [
      "appointmentId (PK)", "patientId (FK)", "patientName", "patientEmail",
      "doctorId (FK)", "doctorName", "department", "appointmentDate", "timeSlot",
      "type", "status", "notes", "medicalNotes", "qrCode", "bookingReference",
      "isCheckedIn", "cancelReason", "rescheduleReason", "reminders",
    ],
  },
  {
    id: "medical_documents", x: 2300, y: 890, w: 595,
    title: "medical_documents", subtitle: "uploaded file metadata",
    header: "#2b6cb0", accent: "#e3f0ff",
    fields: [
      "documentId (PK)", "userId (FK)", "name", "type", "notes", "fileName", "url",
      "storagePath", "uploadedAt", "updatedAt", "addedBy", "addedByRole",
      "addedByName", "appointmentId (FK)",
    ],
  },
  {
    id: "doctor_patient_access", x: 2165, y: 1845, w: 610,
    title: "doctor_patient_access", subtitle: "scoped document visibility",
    header: "#285e61", accent: "#d7f0f2",
    fields: [
      "accessId (PK)", "doctorId (FK)", "patientId (FK)", "appointmentId (FK)",
      "grantedAt",
    ],
  },
];

const coreEdges = [
  { from: [480, 335], to: [610, 335], c1: [525, 335], c2: [565, 335], label: "1:1 profile", labelX: 545, labelY: 300, color: "#5661b3" },
  { from: [1155, 365], to: [1465, 365], c1: [1245, 365], c2: [1375, 365], label: "0..1 doctor profile", labelX: 1310, labelY: 325, color: "#2f855a" },
  { from: [2375, 365], to: [2005, 365], c1: [2260, 365], c2: [2130, 365], label: "1:N contains", labelX: 2190, labelY: 325, color: "#b7791f" },
  { from: [860, 768], to: [1415, 1035], c1: [900, 880], c2: [1185, 1020], label: "patientId", labelX: 1120, labelY: 930, color: "#c05621" },
  { from: [1730, 684], to: [1730, 900], c1: [1730, 760], c2: [1730, 820], label: "doctorId", labelX: 1850, labelY: 790, color: "#c05621" },
  { from: [2645, 566], to: [1985, 1035], c1: [2600, 740], c2: [2210, 950], label: "department", labelX: 2290, labelY: 800, color: "#c05621" },
  { from: [2035, 1235], to: [2300, 1235], c1: [2110, 1235], c2: [2210, 1235], label: "0..N files", labelX: 2170, labelY: 1195, color: "#2b6cb0" },
  { from: [980, 768], to: [2300, 1095], c1: [1180, 1150], c2: [1885, 1080], label: "userId / addedBy", labelX: 1630, labelY: 1138, color: "#2b6cb0" },
  { from: [790, 768], to: [790, 920], c1: [790, 810], c2: [790, 865], label: "1:N receives", labelX: 938, labelY: 845, color: "#805ad5" },
  { from: [1415, 1385], to: [1205, 1180], c1: [1320, 1360], c2: [1255, 1295], label: "appointmentId", labelX: 1290, labelY: 1305, color: "#805ad5" },
  { from: [530, 1030], to: [650, 1030], c1: [565, 1030], c2: [610, 1030], label: "1:N devices", labelX: 590, labelY: 990, color: "#5661b3" },
  { from: [1860, 1597], to: [2380, 1845], c1: [1950, 1770], c2: [2200, 1800], label: "appointmentId", labelX: 2140, labelY: 1738, color: "#285e61" },
  { from: [1780, 684], to: [2285, 1845], c1: [2010, 1010], c2: [2070, 1580], label: "doctorId", labelX: 2150, labelY: 1480, color: "#285e61" },
  { from: [1110, 768], to: [2165, 1915], c1: [1250, 1540], c2: [1740, 1870], label: "patientId", labelX: 1670, labelY: 1755, color: "#285e61" },
];

const supportEntities = [
  {
    id: "admin_users", x: 110, y: 210, w: 510, h: 340,
    title: "users", subtitle: "admin and super admin reference",
    header: "#1f6f78", accent: "#d7f0f2",
    fields: [
      "userId / uid (PK)", "email", "fullName", "role", "isActive",
      "adminPermissions",
    ],
  },
  {
    id: "doctor_ref", x: 110, y: 790, w: 510, h: 310,
    title: "doctors", subtitle: "doctor reference",
    header: "#2f855a", accent: "#ddf3e5",
    fields: ["doctorId (PK)", "userId (FK)", "doctorName", "isAvailable"],
  },
  {
    id: "appointment_ref", x: 110, y: 1320, w: 510, h: 345,
    title: "appointments", subtitle: "booking reference",
    header: "#c05621", accent: "#ffeadb",
    fields: [
      "appointmentId (PK)", "doctorId (FK)", "appointmentDate", "timeSlot",
      "status",
    ],
  },
  {
    id: "audit", x: 840, y: 190, w: 600,
    title: "admin_audit_logs", subtitle: "governance event history",
    header: "#6b46c1", accent: "#efe8ff",
    fields: [
      "logId (PK)", "actorUid (FK)", "actorRole", "actorName", "targetUid (FK)",
      "targetName", "action", "before", "after", "metadata", "createdAt",
    ],
  },
  {
    id: "sends", x: 1605, y: 190, w: 600,
    title: "admin_notification_sends", subtitle: "admin send audit records",
    header: "#805ad5", accent: "#efe8ff",
    fields: [
      "sendId (PK)", "adminUid (FK)", "idempotencyKey", "recipientType",
      "recipientCount", "title", "body", "createdAt",
    ],
  },
  {
    id: "rate_limits", x: 2470, y: 190, w: 550,
    title: "admin_notification_rate_limits", subtitle: "send cooldown state",
    header: "#805ad5", accent: "#efe8ff",
    fields: ["adminUid (PK/FK)", "lastSendAt"],
  },
  {
    id: "availability_requests", x: 840, y: 880, w: 615,
    title: "doctor_availability_requests", subtitle: "unavailable request review",
    header: "#2f855a", accent: "#ddf3e5",
    fields: [
      "requestId (PK)", "doctorId (FK)", "doctorName", "status", "note",
      "reviewedBy (FK)", "reviewedAt", "createdAt",
    ],
  },
  {
    id: "availability_usage", x: 1670, y: 880, w: 535,
    title: "doctor_availability_usage", subtitle: "monthly usage counter",
    header: "#2f855a", accent: "#ddf3e5",
    fields: ["usageId (PK)", "doctorId (FK)", "month", "approvedCount"],
  },
  {
    id: "slot_locks", x: 840, y: 1510, w: 615,
    title: "appointment_slot_locks", subtitle: "double-booking prevention",
    header: "#c05621", accent: "#ffeadb",
    fields: [
      "slotLockId (PK)", "doctorId (FK)", "date", "timeSlot", "appointmentId (FK)",
      "lockedAt",
    ],
  },
  {
    id: "notifications_ref", x: 2470, y: 790, w: 550, h: 345,
    title: "notifications", subtitle: "records created for recipients",
    header: "#805ad5", accent: "#efe8ff",
    fields: [
      "notificationId (PK)", "userId (FK)", "title", "body", "type",
      "createdAt", "isDelivered",
    ],
  },
];

const supportEdges = [
  { from: [620, 360], to: [840, 360], c1: [690, 360], c2: [760, 360], label: "actorUid / targetUid", labelX: 735, labelY: 320, color: "#6b46c1" },
  { from: [620, 420], to: [1605, 385], c1: [930, 545], c2: [1300, 505], label: "adminUid", labelX: 1130, labelY: 500, color: "#805ad5" },
  { from: [2205, 365], to: [2470, 300], c1: [2285, 365], c2: [2385, 300], label: "cooldown", labelX: 2340, labelY: 312, color: "#805ad5" },
  { from: [2205, 500], to: [2470, 930], c1: [2325, 625], c2: [2375, 850], label: "creates N notifications", labelX: 2375, labelY: 700, color: "#805ad5" },
  { from: [620, 960], to: [840, 1015], c1: [690, 960], c2: [760, 1015], label: "doctorId", labelX: 735, labelY: 930, color: "#2f855a" },
  { from: [620, 460], to: [840, 1190], c1: [710, 675], c2: [720, 1050], label: "reviewedBy", labelX: 745, labelY: 795, color: "#2f855a", dashed: true },
  { from: [1455, 1040], to: [1670, 1010], c1: [1520, 1040], c2: [1595, 1010], label: "approved usage", labelX: 1562, labelY: 985, color: "#2f855a" },
  { from: [620, 980], to: [840, 1605], c1: [720, 1150], c2: [730, 1480], label: "doctorId", labelX: 725, labelY: 1325, color: "#c05621" },
  { from: [620, 1490], to: [840, 1705], c1: [690, 1490], c2: [760, 1705], label: "appointmentId", labelX: 735, labelY: 1585, color: "#c05621" },
];

const page1 = svgPage(
  "Figure 2A: Core Entity Relationship Diagram",
  "University Health Center System - application data collections",
  coreEntities,
  coreEdges,
  [
    noteSvg(100, 2190, 1290, [
      "PK = primary document identifier, FK = stored reference field.",
      "All field names are taken from the updated Table 1.",
    ], "#f4fbfa"),
    noteSvg(1530, 2190, 1290, [
      "The diagram is vector SVG so text remains sharp in PDF export.",
      "This page covers users, doctors, bookings, documents, notifications, and access scope.",
    ], "#f8f7ff"),
  ],
);

const page2 = svgPage(
  "Figure 2B: Governance and Support Entity Relationships",
  "University Health Center System - audit, availability, slot-lock, and admin-notification collections",
  supportEntities,
  supportEdges,
  [
    noteSvg(110, 2050, 1420, [
      "Reference entities repeat only the key fields needed to show relationships.",
      "Full users, doctors, appointments, and notifications fields are shown in Figure 2A.",
    ], "#f4fbfa"),
    noteSvg(1660, 2050, 1360, [
      "Support collections protect administrative actions, prevent double booking,",
      "limit notification sending, and track doctor unavailable-request usage.",
    ], "#fff8ed"),
  ],
);

const html = `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Figure 2 ER Diagram Preview</title>
  <style>
    @page { size: 11in 8.5in; margin: 0; }
    body { margin: 0; background: #dfe6ec; font-family: Arial, Helvetica, sans-serif; }
    .page { width: 11in; height: 8.5in; margin: 24px auto; background: white; box-shadow: 0 12px 40px rgba(31, 41, 51, .18); }
    .page svg { display: block; width: 100%; height: 100%; }
    @media print {
      body { background: white; }
      .page { margin: 0; box-shadow: none; page-break-after: always; }
    }
  </style>
</head>
<body>
  <section class="page">${page1}</section>
  <section class="page">${page2}</section>
</body>
</html>`;

fs.writeFileSync(path.join(OUT_DIR, "figure2a-core-erd.svg"), page1, "utf8");
fs.writeFileSync(path.join(OUT_DIR, "figure2b-governance-support-erd.svg"), page2, "utf8");
fs.writeFileSync(path.join(OUT_DIR, "figure2-preview.html"), html, "utf8");

async function renderOptional() {
  try {
    const sharp = require("sharp");
    await sharp(Buffer.from(page1), { density: 300 })
      .resize({ width: 3300, height: 2550, fit: "fill" })
      .png()
      .toFile(path.join(OUT_DIR, "figure2a-core-erd.png"));
    await sharp(Buffer.from(page2), { density: 300 })
      .resize({ width: 3300, height: 2550, fit: "fill" })
      .png()
      .toFile(path.join(OUT_DIR, "figure2b-governance-support-erd.png"));
  } catch (error) {
    console.warn(`PNG preview skipped: ${error.message}`);
  }

  try {
    const { chromium } = require("playwright");
    const browser = await chromium.launch({ headless: true });
    const page = await browser.newPage({ viewport: { width: 1650, height: 1275 }, deviceScaleFactor: 2 });
    await page.goto(`file://${path.join(OUT_DIR, "figure2-preview.html").replace(/\\/g, "/")}`);
    await page.pdf({
      path: path.join(OUT_DIR, "figure2-preview.pdf"),
      width: "11in",
      height: "8.5in",
      printBackground: true,
      margin: { top: "0", right: "0", bottom: "0", left: "0" },
    });
    await browser.close();
  } catch (error) {
    console.warn(`PDF preview skipped: ${error.message}`);
  }
}

renderOptional().then(() => {
  console.log(`Generated Figure 2 ERD preview assets in ${OUT_DIR}`);
});
