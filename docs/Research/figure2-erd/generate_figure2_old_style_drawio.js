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

const styles = {
  entity: "rounded=0;whiteSpace=wrap;html=1;fillColor=#b8e94b;strokeColor=#6c9f1b;strokeWidth=3;fontStyle=1;fontSize=22;fontColor=#1f2a1f;",
  relationship: "rhombus;whiteSpace=wrap;html=1;fillColor=#5acfe6;strokeColor=#1590ad;strokeWidth=3;fontStyle=1;fontSize=15;fontColor=#16333a;",
  attribute: "ellipse;whiteSpace=wrap;html=1;fillColor=#b8e94b;strokeColor=#6c9f1b;strokeWidth=3;fontStyle=1;fontSize=16;fontColor=#1f2a1f;",
  line: "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;endArrow=none;strokeColor=#9aa5ad;strokeWidth=2;",
  relLine: "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;endArrow=none;strokeColor=#7e8a92;strokeWidth=3;",
  cardinality: "text;html=1;strokeColor=none;fillColor=none;fontSize=18;fontStyle=1;fontColor=#333333;",
  title: "text;html=1;strokeColor=none;fillColor=none;fontSize=42;fontStyle=1;fontColor=#1f2933;",
  note: "rounded=1;whiteSpace=wrap;html=1;fillColor=#f8fbfd;strokeColor=#b9c7d3;strokeWidth=2;fontSize=18;fontColor=#33444e;",
};

function shape(id, value, style, x, y, w, h) {
  return `<mxCell id="${id}" value="${esc(value)}" style="${style}" vertex="1" parent="1"><mxGeometry x="${x}" y="${y}" width="${w}" height="${h}" as="geometry"/></mxCell>`;
}

function edge(id, source, target, style = styles.line, value = "") {
  return `<mxCell id="${id}" value="${esc(value)}" style="${style}" edge="1" parent="1" source="${source}" target="${target}"><mxGeometry relative="1" as="geometry"/></mxCell>`;
}

function label(id, value, x, y, w = 80, h = 32) {
  return shape(id, value, styles.cardinality, x, y, w, h);
}

function model(title, cells) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<mxGraphModel dx="3300" dy="2550" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="${W}" pageHeight="${H}" math="0" shadow="0">
  <root>
    <mxCell id="0"/>
    <mxCell id="1" parent="0"/>
    ${shape("page-title", title, styles.title, 0, 30, W, 70)}
    ${cells.join("\n    ")}
  </root>
</mxGraphModel>`;
}

function svgShape(item) {
  const common = `stroke-width="3"`;
  if (item.kind === "entity") {
    return `<rect x="${item.x}" y="${item.y}" width="${item.w}" height="${item.h}" fill="#b8e94b" stroke="#6c9f1b" ${common}/><text x="${item.x + item.w / 2}" y="${item.y + item.h / 2 + 8}" text-anchor="middle" class="entity">${esc(item.value)}</text>`;
  }
  if (item.kind === "relationship") {
    const cx = item.x + item.w / 2;
    const cy = item.y + item.h / 2;
    return `<polygon points="${cx},${item.y} ${item.x + item.w},${cy} ${cx},${item.y + item.h} ${item.x},${cy}" fill="#5acfe6" stroke="#1590ad" ${common}/>${svgMultilineText(item.value, cx, cy - 10, "rel", "middle", 20)}`;
  }
  if (item.kind === "attribute") {
    return `<ellipse cx="${item.x + item.w / 2}" cy="${item.y + item.h / 2}" rx="${item.w / 2}" ry="${item.h / 2}" fill="#b8e94b" stroke="#6c9f1b" ${common}/>${svgMultilineText(item.value, item.x + item.w / 2, item.y + item.h / 2 - 14, "attr", "middle", 20)}`;
  }
  if (item.kind === "label") {
    return `<text x="${item.x}" y="${item.y}" class="card">${esc(item.value)}</text>`;
  }
  if (item.kind === "note") {
    return `<rect x="${item.x}" y="${item.y}" width="${item.w}" height="${item.h}" rx="18" fill="#f8fbfd" stroke="#b9c7d3" stroke-width="2"/>${svgMultilineText(item.value, item.x + 26, item.y + 34, "note", "start", 28)}`;
  }
  return "";
}

function svgMultilineText(value, x, y, cls, anchor, step) {
  return String(value).split("\n").map((line, index) =>
    `<text x="${x}" y="${y + index * step}" text-anchor="${anchor}" class="${cls}">${esc(line)}</text>`
  ).join("");
}

function svgEdge(itemById, edgeDef) {
  const s = itemById[edgeDef.source];
  const t = itemById[edgeDef.target];
  if (!s || !t) return "";
  const sx = s.x + s.w / 2;
  const sy = s.y + s.h / 2;
  const tx = t.x + t.w / 2;
  const ty = t.y + t.h / 2;
  return `<line x1="${sx}" y1="${sy}" x2="${tx}" y2="${ty}" stroke="${edgeDef.rel ? "#7e8a92" : "#9aa5ad"}" stroke-width="${edgeDef.rel ? 3 : 2}"/>`;
}

function svgPage(title, items, edgeDefs, fileBase) {
  const itemById = Object.fromEntries(items.map((item) => [item.id, item]));
  const svg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="11in" height="8.5in" viewBox="0 0 ${W} ${H}">
  <style>
    .title { font: 700 42px Arial, Helvetica, sans-serif; fill: #1f2933; }
    .entity { font: 700 22px Arial, Helvetica, sans-serif; fill: #1f2a1f; }
    .attr { font: 700 16px Arial, Helvetica, sans-serif; fill: #1f2a1f; }
    .rel { font: 700 15px Arial, Helvetica, sans-serif; fill: #16333a; }
    .card { font: 700 18px Arial, Helvetica, sans-serif; fill: #333333; }
    .note { font: 18px Arial, Helvetica, sans-serif; fill: #33444e; }
  </style>
  <rect width="${W}" height="${H}" fill="#ffffff"/>
  <text x="${W / 2}" y="84" class="title" text-anchor="middle">${esc(title)}</text>
  <g id="edges">${edgeDefs.map((e) => svgEdge(itemById, e)).join("\n")}</g>
  <g id="nodes">${items.map(svgShape).join("\n")}</g>
</svg>`;
  fs.writeFileSync(path.join(OUT_DIR, `${fileBase}.svg`), svg, "utf8");
  return svg;
}

function entity(id, value, x, y, w = 230, h = 72) {
  return { id, kind: "entity", value, x, y, w, h };
}

function rel(id, value, x, y, w = 150, h = 90) {
  return { id, kind: "relationship", value, x, y, w, h };
}

function attr(id, value, x, y, w = 210, h = 76) {
  return { id, kind: "attribute", value, x, y, w, h };
}

function card(id, value, x, y) {
  return { id, kind: "label", value, x, y, w: 50, h: 25 };
}

function note(id, value, x, y, w, h) {
  return { id, kind: "note", value, x, y, w, h };
}

function mxCellsFrom(items, edges) {
  const out = [];
  for (const item of items) {
    if (item.kind === "entity") out.push(shape(item.id, item.value, styles.entity, item.x, item.y, item.w, item.h));
    if (item.kind === "relationship") out.push(shape(item.id, item.value, styles.relationship, item.x, item.y, item.w, item.h));
    if (item.kind === "attribute") out.push(shape(item.id, item.value.replace(/\n/g, "<br>"), styles.attribute, item.x, item.y, item.w, item.h));
    if (item.kind === "label") out.push(label(item.id, item.value, item.x, item.y));
    if (item.kind === "note") out.push(shape(item.id, item.value.replace(/\n/g, "<br>"), styles.note, item.x, item.y, item.w, item.h));
  }
  for (const e of edges) {
    out.push(edge(e.id, e.source, e.target, e.rel ? styles.relLine : styles.line, e.value || ""));
  }
  return out;
}

const pageAItems = [
  entity("auth", "Firebase Auth", 120, 470),
  attr("auth_uid", "uid\n(PK)", 55, 260, 150, 72),
  attr("auth_email", "email", 230, 260, 150, 72),
  attr("auth_provider", "provider", 55, 720, 170, 72),
  rel("creates_profile", "Creates\nProfile", 390, 455),

  entity("users", "Users", 770, 470),
  attr("users_id", "userId\n(PK)", 650, 260, 190, 72),
  attr("users_identity", "email\nfullName", 855, 250, 210, 82),
  attr("users_contact", "phoneNumber\ndateOfBirth", 635, 690, 230, 82),
  attr("users_health", "bloodType\nallergies", 875, 720, 230, 82),
  attr("users_role", "role\nisActive", 1055, 455, 190, 76),
  attr("users_misc", "studentId staffId\nlanguage googleEmail\nnotificationSettings\nadminPermissions", 585, 840, 330, 118),

  rel("doctor_profile", "Doctor\nProfile", 1260, 455),
  entity("doctors", "Doctors", 1660, 470),
  attr("doctor_id", "doctorId\n(PK)", 1505, 250, 200, 76),
  attr("doctor_user", "userId\n(FK)", 1760, 250, 190, 76),
  attr("doctor_identity", "name email\nphotoUrl", 1450, 710, 245, 88),
  attr("doctor_specialty", "department\nspecialization", 1880, 710, 245, 88),
  attr("doctor_profile_attr", "bio qualifications\nexperienceYears", 1510, 835, 270, 88),
  attr("doctor_schedule", "isAvailable isActive\nweeklySchedule\ndailyNotificationTime", 1840, 835, 320, 105),

  entity("departments", "Departments", 2590, 420),
  attr("dept_key", "key\n(PK)", 2460, 245, 175, 72),
  attr("dept_info", "name description", 2700, 245, 240, 72),
  attr("dept_visual", "iconName\ncolorHex", 2940, 405, 210, 82),
  attr("dept_hours", "workingHours\nisActive\ndoctorCount", 2500, 620, 260, 100),
  rel("contains", "Contains", 2220, 445),

  entity("appointments", "Appointments", 1640, 1260),
  attr("appt_id", "appointmentId\n(PK)", 1515, 1045, 230, 76),
  attr("appt_patient", "patientId (FK)\npatientName\npatientEmail", 1240, 1225, 285, 105),
  attr("appt_doctor", "doctorId (FK)\ndoctorName\ndepartment", 1960, 1200, 285, 105),
  attr("appt_time", "appointmentDate\ntimeSlot", 1360, 1480, 250, 82),
  attr("appt_status", "type status\nisCheckedIn", 1770, 1490, 235, 88),
  attr("appt_notes", "notes\nmedicalNotes", 2025, 1495, 220, 82),
  attr("appt_misc", "qrCode\nbookingReference\ncancelReason\nrescheduleReason\nreminders", 1540, 1670, 315, 130),
  rel("books", "Books", 1085, 930),
  rel("receives", "Receives", 1890, 930),

  entity("notifications", "Notifications", 655, 1610),
  attr("notification_id", "notificationId\n(PK)", 470, 1775, 245, 78),
  attr("notification_user", "userId\n(FK)", 455, 1460, 190, 74),
  attr("notification_body", "title body\ntype data", 830, 1450, 230, 82),
  attr("notification_status", "isRead createdAt\nscheduledFor\nreminderType\nisDelivered", 785, 1760, 300, 120),
  attr("notification_appt", "appointmentId\n(FK)", 1035, 1620, 235, 78),
  rel("triggers", "Triggers", 1260, 1465),
  rel("notifies", "Receives", 520, 1230),

  entity("user_tokens", "User Tokens", 130, 1570),
  attr("token_user", "userId\n(FK)", 55, 1400, 175, 72),
  attr("token_id", "token\ntokenHash", 235, 1390, 210, 82),
  attr("token_device", "deviceInfo\ntimezone\nupdatedAt", 130, 1735, 245, 100),
  rel("has_token", "Has\nToken", 400, 1560),

  entity("medical_docs", "Medical\nDocuments", 2490, 1560, 250, 92),
  attr("doc_id", "documentId\n(PK)", 2310, 1750, 230, 78),
  attr("doc_user", "userId\n(FK)", 2260, 1410, 185, 74),
  attr("doc_info", "name type\nnotes", 2760, 1400, 210, 82),
  attr("doc_file", "fileName url\nstoragePath", 2810, 1585, 240, 88),
  attr("doc_audit", "uploadedAt updatedAt\naddedBy addedByRole\naddedByName", 2540, 1790, 330, 112),
  attr("doc_appt", "appointmentId\n(FK)", 2295, 1570, 225, 78),
  rel("attached_to", "Attached\nTo", 2205, 1360),
  rel("uploads", "Uploads", 2160, 1835),

  note("note_a", "Figure 2A keeps the old Chen ERD style: green entities/attributes and blue relationship diamonds.\nAll field names come from the updated Table 1.", 120, 2235, 1390, 120),
  note("note_b", "This page covers core operational collections. The support/governance collections continue in Figure 2B.", 1780, 2235, 1390, 120),

  card("c1", "1", 363, 435),
  card("c2", "1", 565, 435),
  card("c3", "1", 1170, 435),
  card("c4", "0..1", 1435, 435),
  card("c5", "1", 2410, 415),
  card("c6", "N", 2545, 415),
  card("c7", "1", 1030, 900),
  card("c8", "N", 1505, 1175),
  card("c9", "1", 1830, 900),
  card("c10", "N", 1805, 1165),
  card("c11", "N", 690, 1510),
  card("c12", "N", 2310, 1515),
];

const pageAEdges = [
  { id: "e_auth_uid", source: "auth_uid", target: "auth" },
  { id: "e_auth_email", source: "auth_email", target: "auth" },
  { id: "e_auth_provider", source: "auth_provider", target: "auth" },
  { id: "e_auth_profile_1", source: "auth", target: "creates_profile", rel: true },
  { id: "e_auth_profile_2", source: "creates_profile", target: "users", rel: true },
  { id: "e_users_id", source: "users_id", target: "users" },
  { id: "e_users_identity", source: "users_identity", target: "users" },
  { id: "e_users_contact", source: "users_contact", target: "users" },
  { id: "e_users_health", source: "users_health", target: "users" },
  { id: "e_users_role", source: "users_role", target: "users" },
  { id: "e_users_misc", source: "users_misc", target: "users" },
  { id: "e_user_doctor_1", source: "users", target: "doctor_profile", rel: true },
  { id: "e_user_doctor_2", source: "doctor_profile", target: "doctors", rel: true },
  { id: "e_doctor_id", source: "doctor_id", target: "doctors" },
  { id: "e_doctor_user", source: "doctor_user", target: "doctors" },
  { id: "e_doctor_identity", source: "doctor_identity", target: "doctors" },
  { id: "e_doctor_specialty", source: "doctor_specialty", target: "doctors" },
  { id: "e_doctor_profile_attr", source: "doctor_profile_attr", target: "doctors" },
  { id: "e_doctor_schedule", source: "doctor_schedule", target: "doctors" },
  { id: "e_dept_key", source: "dept_key", target: "departments" },
  { id: "e_dept_info", source: "dept_info", target: "departments" },
  { id: "e_dept_visual", source: "dept_visual", target: "departments" },
  { id: "e_dept_hours", source: "dept_hours", target: "departments" },
  { id: "e_contains_1", source: "departments", target: "contains", rel: true },
  { id: "e_contains_2", source: "contains", target: "doctors", rel: true },
  { id: "e_books_1", source: "users", target: "books", rel: true },
  { id: "e_books_2", source: "books", target: "appointments", rel: true },
  { id: "e_receives_1", source: "doctors", target: "receives", rel: true },
  { id: "e_receives_2", source: "receives", target: "appointments", rel: true },
  { id: "e_appt_id", source: "appt_id", target: "appointments" },
  { id: "e_appt_patient", source: "appt_patient", target: "appointments" },
  { id: "e_appt_doctor", source: "appt_doctor", target: "appointments" },
  { id: "e_appt_time", source: "appt_time", target: "appointments" },
  { id: "e_appt_status", source: "appt_status", target: "appointments" },
  { id: "e_appt_notes", source: "appt_notes", target: "appointments" },
  { id: "e_appt_misc", source: "appt_misc", target: "appointments" },
  { id: "e_token_user", source: "token_user", target: "user_tokens" },
  { id: "e_token_id", source: "token_id", target: "user_tokens" },
  { id: "e_token_device", source: "token_device", target: "user_tokens" },
  { id: "e_has_token_1", source: "users", target: "has_token", rel: true },
  { id: "e_has_token_2", source: "has_token", target: "user_tokens", rel: true },
  { id: "e_notifies_1", source: "users", target: "notifies", rel: true },
  { id: "e_notifies_2", source: "notifies", target: "notifications", rel: true },
  { id: "e_notification_id", source: "notification_id", target: "notifications" },
  { id: "e_notification_user", source: "notification_user", target: "notifications" },
  { id: "e_notification_body", source: "notification_body", target: "notifications" },
  { id: "e_notification_status", source: "notification_status", target: "notifications" },
  { id: "e_notification_appt", source: "notification_appt", target: "notifications" },
  { id: "e_trigger_1", source: "appointments", target: "triggers", rel: true },
  { id: "e_trigger_2", source: "triggers", target: "notifications", rel: true },
  { id: "e_doc_id", source: "doc_id", target: "medical_docs" },
  { id: "e_doc_user", source: "doc_user", target: "medical_docs" },
  { id: "e_doc_info", source: "doc_info", target: "medical_docs" },
  { id: "e_doc_file", source: "doc_file", target: "medical_docs" },
  { id: "e_doc_audit", source: "doc_audit", target: "medical_docs" },
  { id: "e_doc_appt", source: "doc_appt", target: "medical_docs" },
  { id: "e_attached_1", source: "appointments", target: "attached_to", rel: true },
  { id: "e_attached_2", source: "attached_to", target: "medical_docs", rel: true },
  { id: "e_uploads_1", source: "users", target: "uploads", rel: true },
  { id: "e_uploads_2", source: "uploads", target: "medical_docs", rel: true },
];

const pageBItems = [
  entity("admin_users", "Users", 170, 420),
  attr("admin_user_id", "userId / uid\n(PK)", 70, 245, 215, 76),
  attr("admin_identity", "email\nfullName", 335, 245, 210, 82),
  attr("admin_role", "role isActive\nadminPermissions", 170, 620, 300, 90),

  entity("admin_audit", "Admin Audit\nLogs", 900, 420, 260, 92),
  attr("audit_id", "logId\n(PK)", 760, 245, 190, 76),
  attr("audit_actor", "actorUid\nactorRole\nactorName", 1040, 230, 245, 100),
  attr("audit_target", "targetUid\ntargetName", 1180, 475, 230, 82),
  attr("audit_action", "action", 765, 625, 160, 70),
  attr("audit_change", "before\nafter", 1005, 640, 170, 80),
  attr("audit_meta", "metadata\ncreatedAt", 1195, 645, 220, 80),
  rel("records_action", "Records\nAction", 610, 420),

  entity("admin_sends", "Admin Notification\nSends", 1875, 360, 330, 92),
  attr("send_id", "sendId\n(PK)", 1685, 205, 190, 76),
  attr("send_admin", "adminUid\n(FK)", 1940, 200, 200, 76),
  attr("send_idempotency", "idempotencyKey", 2200, 230, 250, 72),
  attr("send_recipients", "recipientType\nrecipientCount", 1625, 545, 260, 86),
  attr("send_message", "title\nbody", 1945, 560, 180, 78),
  attr("send_created", "createdAt", 2245, 545, 180, 70),
  rel("sends_notifications", "Sends\nNotifications", 2475, 515, 185, 108),

  entity("rate_limits", "Admin Notification\nRate Limits", 2805, 360, 340, 92),
  attr("rate_admin", "adminUid\n(PK/FK)", 2705, 205, 230, 76),
  attr("rate_last", "lastSendAt", 3005, 205, 190, 70),
  rel("limits", "Limits", 2505, 300),

  entity("notifications_ref", "Notifications", 2825, 780),
  attr("notif_ref_id", "notificationId\n(PK)", 2670, 945, 235, 76),
  attr("notif_ref_user", "userId\n(FK)", 2920, 945, 190, 74),
  attr("notif_ref_msg", "title body\ntype createdAt\nisDelivered", 2770, 1130, 310, 105),

  entity("doctors_ref", "Doctors", 180, 1110),
  attr("doctor_ref_id", "doctorId\n(PK)", 65, 925, 205, 76),
  attr("doctor_ref_user", "userId\n(FK)", 315, 925, 190, 74),
  attr("doctor_ref_state", "doctorName\nisAvailable", 185, 1290, 240, 82),

  entity("availability_requests", "Doctor Availability\nRequests", 880, 1080, 330, 92),
  attr("request_id", "requestId\n(PK)", 710, 880, 215, 76),
  attr("request_doctor", "doctorId\n(FK)", 1015, 875, 200, 76),
  attr("request_review", "status note\nreviewedBy\nreviewedAt createdAt", 1220, 1065, 320, 118),
  rel("requests_unavailable", "Requests\nUnavailable", 560, 1080, 180, 105),
  rel("reviews_request", "Reviews", 670, 760, 160, 90),

  entity("availability_usage", "Doctor Availability\nUsage", 1770, 1110, 330, 92),
  attr("usage_id", "usageId\n(PK)", 1605, 930, 205, 76),
  attr("usage_doctor", "doctorId\n(FK)", 1900, 930, 200, 76),
  attr("usage_count", "month\napprovedCount", 1765, 1290, 245, 82),
  rel("tracks_usage", "Tracks\nUsage", 1450, 1235, 160, 95),

  entity("appointments_ref", "Appointments", 180, 1770),
  attr("appt_ref_id", "appointmentId\n(PK)", 45, 1580, 245, 76),
  attr("appt_ref_doctor", "doctorId\n(FK)", 330, 1580, 190, 74),
  attr("appt_ref_slot", "appointmentDate\ntimeSlot\nstatus", 165, 1950, 260, 100),

  entity("slot_locks", "Appointment Slot\nLocks", 880, 1770, 300, 92),
  attr("lock_id", "slotLockId\n(PK)", 720, 1560, 220, 76),
  attr("lock_doctor", "doctorId\n(FK)", 1020, 1560, 200, 76),
  attr("lock_slot", "date\ntimeSlot\nlockedAt", 730, 1945, 235, 100),
  attr("lock_appt", "appointmentId\n(FK)", 1030, 1945, 245, 76),
  rel("locks_slot", "Locks\nSlot", 560, 1770, 160, 92),

  entity("doctor_patient_access", "Doctor Patient\nAccess", 2100, 1740, 320, 92),
  attr("access_id", "accessId\n(PK)", 1880, 1540, 210, 76),
  attr("access_doctor", "doctorId\n(FK)", 2200, 1515, 200, 76),
  attr("access_patient", "patientId\n(FK)", 2460, 1620, 200, 76),
  attr("access_appt", "appointmentId\n(FK)", 1940, 1940, 245, 76),
  attr("access_granted", "grantedAt", 2300, 1950, 175, 70),
  rel("grants_access", "Grants\nAccess", 1580, 1745, 160, 92),

  note("note_b1", "Figure 2B continues the old ERD style for the collections that support governance, availability control, slot locking, admin notification audit, and scoped document access.", 120, 2235, 1540, 125),
  note("note_b2", "Reference entities repeat only the needed keys here. Full field sets for Users, Doctors, Appointments, and Notifications are shown in Figure 2A.", 1780, 2235, 1390, 125),

  card("bc1", "1", 520, 405),
  card("bc2", "N", 780, 405),
  card("bc3", "1", 465, 1065),
  card("bc4", "N", 760, 1065),
  card("bc5", "1", 1255, 1080),
  card("bc6", "N", 1655, 1080),
  card("bc7", "1", 495, 1755),
  card("bc8", "1", 750, 1755),
  card("bc9", "1", 2270, 500),
  card("bc10", "N", 2725, 765),
];

const pageBEdges = [
  { id: "be_admin_user_id", source: "admin_user_id", target: "admin_users" },
  { id: "be_admin_identity", source: "admin_identity", target: "admin_users" },
  { id: "be_admin_role", source: "admin_role", target: "admin_users" },
  { id: "be_records_1", source: "admin_users", target: "records_action", rel: true },
  { id: "be_records_2", source: "records_action", target: "admin_audit", rel: true },
  { id: "be_audit_id", source: "audit_id", target: "admin_audit" },
  { id: "be_audit_actor", source: "audit_actor", target: "admin_audit" },
  { id: "be_audit_target", source: "audit_target", target: "admin_audit" },
  { id: "be_audit_action", source: "audit_action", target: "admin_audit" },
  { id: "be_audit_change", source: "audit_change", target: "admin_audit" },
  { id: "be_audit_meta", source: "audit_meta", target: "admin_audit" },
  { id: "be_admin_send", source: "admin_users", target: "admin_sends", rel: true },
  { id: "be_send_id", source: "send_id", target: "admin_sends" },
  { id: "be_send_admin", source: "send_admin", target: "admin_sends" },
  { id: "be_send_idempotency", source: "send_idempotency", target: "admin_sends" },
  { id: "be_send_recipients", source: "send_recipients", target: "admin_sends" },
  { id: "be_send_message", source: "send_message", target: "admin_sends" },
  { id: "be_send_created", source: "send_created", target: "admin_sends" },
  { id: "be_limits_1", source: "admin_sends", target: "limits", rel: true },
  { id: "be_limits_2", source: "limits", target: "rate_limits", rel: true },
  { id: "be_rate_admin", source: "rate_admin", target: "rate_limits" },
  { id: "be_rate_last", source: "rate_last", target: "rate_limits" },
  { id: "be_sends_1", source: "admin_sends", target: "sends_notifications", rel: true },
  { id: "be_sends_2", source: "sends_notifications", target: "notifications_ref", rel: true },
  { id: "be_notif_ref_id", source: "notif_ref_id", target: "notifications_ref" },
  { id: "be_notif_ref_user", source: "notif_ref_user", target: "notifications_ref" },
  { id: "be_notif_ref_msg", source: "notif_ref_msg", target: "notifications_ref" },
  { id: "be_doctor_ref_id", source: "doctor_ref_id", target: "doctors_ref" },
  { id: "be_doctor_ref_user", source: "doctor_ref_user", target: "doctors_ref" },
  { id: "be_doctor_ref_state", source: "doctor_ref_state", target: "doctors_ref" },
  { id: "be_req_1", source: "doctors_ref", target: "requests_unavailable", rel: true },
  { id: "be_req_2", source: "requests_unavailable", target: "availability_requests", rel: true },
  { id: "be_review_1", source: "admin_users", target: "reviews_request", rel: true },
  { id: "be_review_2", source: "reviews_request", target: "availability_requests", rel: true },
  { id: "be_request_id", source: "request_id", target: "availability_requests" },
  { id: "be_request_doctor", source: "request_doctor", target: "availability_requests" },
  { id: "be_request_review", source: "request_review", target: "availability_requests" },
  { id: "be_tracks_1", source: "availability_requests", target: "tracks_usage", rel: true },
  { id: "be_tracks_2", source: "tracks_usage", target: "availability_usage", rel: true },
  { id: "be_usage_id", source: "usage_id", target: "availability_usage" },
  { id: "be_usage_doctor", source: "usage_doctor", target: "availability_usage" },
  { id: "be_usage_count", source: "usage_count", target: "availability_usage" },
  { id: "be_appt_ref_id", source: "appt_ref_id", target: "appointments_ref" },
  { id: "be_appt_ref_doctor", source: "appt_ref_doctor", target: "appointments_ref" },
  { id: "be_appt_ref_slot", source: "appt_ref_slot", target: "appointments_ref" },
  { id: "be_locks_1", source: "appointments_ref", target: "locks_slot", rel: true },
  { id: "be_locks_2", source: "locks_slot", target: "slot_locks", rel: true },
  { id: "be_lock_id", source: "lock_id", target: "slot_locks" },
  { id: "be_lock_doctor", source: "lock_doctor", target: "slot_locks" },
  { id: "be_lock_slot", source: "lock_slot", target: "slot_locks" },
  { id: "be_lock_appt", source: "lock_appt", target: "slot_locks" },
  { id: "be_grants_1", source: "appointments_ref", target: "grants_access", rel: true },
  { id: "be_grants_2", source: "grants_access", target: "doctor_patient_access", rel: true },
  { id: "be_access_id", source: "access_id", target: "doctor_patient_access" },
  { id: "be_access_doctor", source: "access_doctor", target: "doctor_patient_access" },
  { id: "be_access_patient", source: "access_patient", target: "doctor_patient_access" },
  { id: "be_access_appt", source: "access_appt", target: "doctor_patient_access" },
  { id: "be_access_granted", source: "access_granted", target: "doctor_patient_access" },
];

const modelA = model("Figure 2A: Entity Relationship Diagram of the University Health Center System", mxCellsFrom(pageAItems, pageAEdges));
const modelB = model("Figure 2B: Entity Relationship Diagram of the University Health Center System", mxCellsFrom(pageBItems, pageBEdges));

fs.writeFileSync(path.join(OUT_DIR, "figure2a-old-style.drawio.xml"), modelA, "utf8");
fs.writeFileSync(path.join(OUT_DIR, "figure2b-old-style.drawio.xml"), modelB, "utf8");
fs.writeFileSync(path.join(OUT_DIR, "figure2a-old-style.drawio"), modelA, "utf8");
fs.writeFileSync(path.join(OUT_DIR, "figure2b-old-style.drawio"), modelB, "utf8");

function withoutXmlDeclaration(xml) {
  return xml.replace(/^<\?xml[^>]*>\s*/u, "");
}

const drawioFile = `<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="app.diagrams.net" agent="Codex" version="26.0.0" type="device">
  <diagram id="figure2a-old-style" name="Figure 2A">
${withoutXmlDeclaration(modelA)}
  </diagram>
  <diagram id="figure2b-old-style" name="Figure 2B">
${withoutXmlDeclaration(modelB)}
  </diagram>
</mxfile>`;

const drawioFileA = `<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="app.diagrams.net" agent="Codex" version="26.0.0" type="device">
  <diagram id="figure2a-old-style" name="Figure 2A">
${withoutXmlDeclaration(modelA)}
  </diagram>
</mxfile>`;

const drawioFileB = `<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="app.diagrams.net" agent="Codex" version="26.0.0" type="device">
  <diagram id="figure2b-old-style" name="Figure 2B">
${withoutXmlDeclaration(modelB)}
  </diagram>
</mxfile>`;

fs.writeFileSync(path.join(OUT_DIR, "figure2A.drawio"), drawioFileA, "utf8");
fs.writeFileSync(path.join(OUT_DIR, "figure2B.drawio"), drawioFileB, "utf8");

const svgA = svgPage("Figure 2A: Entity Relationship Diagram of the University Health Center System", pageAItems, pageAEdges, "figure2a-old-style");
const svgB = svgPage("Figure 2B: Entity Relationship Diagram of the University Health Center System", pageBItems, pageBEdges, "figure2b-old-style");

async function renderPng() {
  try {
    const sharp = require("sharp");
    await sharp(Buffer.from(svgA), { density: 300 })
      .resize({ width: 3300, height: 2550, fit: "fill" })
      .png()
      .toFile(path.join(OUT_DIR, "figure2a-old-style.png"));
    await sharp(Buffer.from(svgB), { density: 300 })
      .resize({ width: 3300, height: 2550, fit: "fill" })
      .png()
      .toFile(path.join(OUT_DIR, "figure2b-old-style.png"));
  } catch (error) {
    console.warn(`PNG render skipped: ${error.message}`);
  }
}

renderPng().then(() => {
  console.log(`Generated old-style draw.io Figure 2 assets in ${OUT_DIR}`);
});
