# Doctor Access to Patient Medical Documents — Implementation Plan

## Feature Summary

When a doctor **confirms** an appointment, they gain access to the patient's medical documents.
The doctor can **view** all patient documents, **add** new documents (medicines, prescriptions, etc.),
and **edit/delete** only documents they personally added. When the appointment is **completed**,
the doctor retains **read-only** access. The patient sees all documents (their own + doctor-added)
with clear attribution showing who added each document and when.

---

## Decisions

| Decision | Choice |
|----------|--------|
| Access window | Confirmed → Completed status (doctor controls both endpoints) |
| Post-appointment | Read-only after completion |
| Edit permissions | Doctor edits only their own documents |
| UI entry point | Button in appointment detail screen |
| Architecture | Refactor to Model → Repository → Provider first |
| Document types | Add new "Medicine" type (6 total) |

---

## Current State (Problems)

The existing `medical_documents_screen.dart` (946 lines) is **monolithic**:
- All Firestore + Storage logic directly in the widget (no model, no repository, no provider)
- Uses raw `Map<String, dynamic>` instead of a typed model
- This is the ONLY feature that doesn't follow the codebase's Model → Repo → Provider → Screen pattern
- No doctor access to patient documents exists anywhere

---

## Firestore Schema

**Collection:** `medical_documents` (existing — adding 4 new fields)

```
medical_documents/{auto-id}
  ├── userId: String           // patient's auth UID (EXISTING)
  ├── name: String             // document display name (EXISTING)
  ├── type: String             // EXISTING + adding 'medicine'
  ├── notes: String            // optional notes (EXISTING)
  ├── fileName: String         // original file name (EXISTING)
  ├── url: String              // Firebase Storage download URL (EXISTING)
  ├── storagePath: String      // Storage bucket path (EXISTING)
  ├── uploadedAt: Timestamp    // server timestamp (EXISTING)
  ├── updatedAt: Timestamp     // server timestamp on edit (EXISTING)
  ├── addedBy: String          // NEW — auth UID of who added
  ├── addedByRole: String      // NEW — 'patient' or 'doctor'
  ├── addedByName: String      // NEW — display name of uploader
  └── appointmentId: String?   // NEW — linked appointment (doctor-added only)
```

**Backward compatibility:** Old documents missing new fields default to:
`addedBy = userId`, `addedByRole = 'patient'`, `addedByName = ''`, `appointmentId = null`

**Document types (6):** `lab_results`, `prescription`, `medical_record`, `imaging`, `medicine` (NEW), `other`

---

## Files Overview

### New Files (4)

| # | File | Purpose |
|---|------|---------|
| 1 | `lib/data/models/medical_document_model.dart` | `DocumentType` enum + `MedicalDocumentModel` class |
| 2 | `lib/data/repositories/document_repository.dart` | Firestore + Storage CRUD operations |
| 3 | `lib/providers/document_provider.dart` | ChangeNotifier state management |
| 4 | `lib/screens/doctor/documents/doctor_patient_documents_screen.dart` | Doctor's view of patient documents |

### Modified Files (7)

| # | File | Change |
|---|------|--------|
| 5 | `lib/main.dart` | Register `DocumentProvider` in MultiProvider |
| 6 | `lib/l10n/app_en.arb` | Add ~12 new l10n keys |
| 7 | `lib/l10n/app_ar.arb` | Add ~12 new l10n keys (Arabic) |
| 8 | `lib/l10n/app_ku.arb` | Add ~12 new l10n keys (Kurdish) |
| 9 | `lib/screens/patient/documents/medical_documents_screen.dart` | Refactor to Provider + attribution display |
| 10 | `lib/screens/doctor/appointments/doctor_appointment_detail_screen.dart` | Add "Patient Documents" button |
| 11 | `firestore.rules` | Add `medical_documents` collection rules |

---

## Phases (9 Antigravity Prompts)

### Phase 1 — MedicalDocumentModel (NEW FILE)
**File:** `lib/data/models/medical_document_model.dart`

- `DocumentType` enum with 6 values: `labResults, prescription, medicalRecord, imaging, medicine, other`
- `MedicalDocumentModel` class — all `final` fields
- `factory fromFirestore(DocumentSnapshot)` with `??` fallbacks for backward compat
- `Map<String, dynamic> toFirestore()` method
- `copyWith(...)` method
- Fields: `id`, `userId`, `name`, `type` (DocumentType), `notes`, `fileName`, `url`,
  `storagePath`, `uploadedAt`, `updatedAt`, `addedBy`, `addedByRole`, `addedByName`, `appointmentId`

**Pattern reference:** `lib/data/models/notification_model.dart`

---

### Phase 2 — DocumentRepository (NEW FILE)
**File:** `lib/data/repositories/document_repository.dart`

Methods:
- `Stream<List<MedicalDocumentModel>> streamDocuments(String userId)` — real-time stream ordered by `uploadedAt` desc
- `Future<String> addDocument(MedicalDocumentModel doc)` — `.add()` then `.update({'id': docRef.id})`
- `Future<void> updateDocument(String docId, Map<String, dynamic> data)` — update metadata + `updatedAt`
- `Future<void> deleteDocument(String docId, String storagePath)` — delete Firestore doc + Storage file
- `Future<Map<String, String>> uploadFile(String userId, Uint8List bytes, String fileName)` — upload to `medical_documents/{userId}/{epochMillis}.{ext}`, return `{'url': ..., 'storagePath': ...}`

**Pattern reference:** `lib/data/repositories/notification_repository.dart`

---

### Phase 3 — DocumentProvider (NEW FILE)
**File:** `lib/providers/document_provider.dart`

- Extends `ChangeNotifier`
- Private `DocumentRepository _repo`
- State: `bool _isUploading`, `double _uploadProgress`, `String? _error`
- `Stream<List<MedicalDocumentModel>> streamDocuments(String userId)` — passthrough
- `Future<bool> uploadAndAddDocument({userId, name, type, notes, bytes, fileName, addedBy, addedByRole, addedByName, appointmentId})` — upload file + create Firestore doc
- `Future<bool> updateDocument(String docId, Map<String, dynamic> data)` — update metadata
- `Future<bool> deleteDocument(String docId, String storagePath)` — delete both

**Pattern reference:** `lib/providers/notification_provider.dart`

---

### Phase 4 — Register Provider (EDIT)
**File:** `lib/main.dart`

Add one line to MultiProvider list (after line 127):
```dart
ChangeNotifierProvider(create: (_) => DocumentProvider()),
```
Also add import: `import 'providers/document_provider.dart';`

---

### Phase 5 — Localization (EDIT x 3 + regenerate)
**Files:** `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`, `lib/l10n/app_ku.arb`

New keys to add:

| Key | EN | AR | KU |
|-----|----|----|-----|
| `medicine` | Medicine | دواء | دەرمان |
| `patientDocuments` | Patient Documents | مستندات المريض | بەڵگەنامەکانی نەخۆش |
| `viewPatientDocuments` | View and manage patient's medical documents | عرض وإدارة المستندات الطبية للمريض | بینین و بەڕێوەبردنی بەڵگەنامە پزیشکییەکانی نەخۆش |
| `addDocument` | Add Document | إضافة مستند | زیادکردنی بەڵگەنامە |
| `addedByDoctor` | Added by Dr. {name} | أضافه د. {name} | زیادکراوە لەلایەن د. {name} |
| `addedByPatient` | Added by patient | أضافه المريض | زیادکراوە لەلایەن نەخۆش |
| `readOnlyMode` | Read-only | للقراءة فقط | تەنها خوێندنەوە |
| `appointmentCompletedReadOnly` | This appointment is completed. Documents are read-only. | هذا الموعد مكتمل. المستندات للقراءة فقط. | ئەم چاوپێکەوتنە تەواو بووە. بەڵگەنامەکان تەنها خوێندنەوەن. |
| `noEditPermission` | You can only edit documents you added | يمكنك فقط تعديل المستندات التي أضفتها | تەنها دەتوانیت ئەو بەڵگەنامانە دەستکاری بکەیت کە خۆت زیادت کردووە |
| `documentsCount` | {count} documents | {count} مستند | {count} بەڵگەنامە |
| `doctorDocument` | Doctor Document | مستند الطبيب | بەڵگەنامەی دکتۆر |
| `myDocument` | My Document | مستندي | بەڵگەنامەی من |

Then run: `flutter gen-l10n`

---

### Phase 6 — Refactor Patient MedicalDocumentsScreen (EDIT)
**File:** `lib/screens/patient/documents/medical_documents_screen.dart` (946 lines -> rewrite)

Changes:
1. Remove `_firestore` and `_storage` instance fields — use `DocumentProvider` instead
2. Replace `StreamBuilder<QuerySnapshot>` with `StreamBuilder<List<MedicalDocumentModel>>`
3. Replace raw `Map<String, dynamic>` with `MedicalDocumentModel` throughout
4. Add `'medicine'` to `_getDocumentTypes()` list with icon `Icons.medication_liquid`
5. In `_buildDocumentCard()`: show attribution badge for doctor-added docs ("Added by Dr. X")
6. In popup menu: hide Edit/Delete for docs where `addedByRole == 'doctor'` (patient can't edit doctor's docs)
7. Upload dialog: pass `addedBy: user.id`, `addedByRole: 'patient'`, `addedByName: user.name` to provider
8. Keep same visual style, layout, and UX

---

### Phase 7 — DoctorPatientDocumentsScreen (NEW FILE)
**File:** `lib/screens/doctor/documents/doctor_patient_documents_screen.dart`

Constructor parameters:
- `String patientId` — patient's auth UID (from `appointment.patientId`)
- `String patientName` — for AppBar title
- `String appointmentId` — link new docs to this appointment
- `String doctorId` — doctor's auth UID (for `addedBy`)
- `String doctorName` — for `addedByName`
- `bool isReadOnly` — true for completed appointments

Features:
- Streams all docs for `patientId` via `DocumentProvider`
- Document cards show same visual style as patient screen
- Each card shows "My Document" or "Doctor Document" badge
- Patient-uploaded docs: popup menu has ONLY "View" (no edit/delete)
- Doctor's own docs: popup menu has "View", "Edit", "Delete" — UNLESS `isReadOnly`
- FAB to add new document — hidden when `isReadOnly`
- If `isReadOnly`: show a subtle banner at top ("This appointment is completed. Documents are read-only.")
- Upload dialog: pass `addedBy: doctorId`, `addedByRole: 'doctor'`, `addedByName: doctorName`, `appointmentId: appointmentId`

---

### Phase 8 — Integrate into DoctorAppointmentDetailScreen (EDIT)
**File:** `lib/screens/doctor/appointments/doctor_appointment_detail_screen.dart` (890 lines)

Add a new section card BETWEEN the Medical Notes section (ends at line ~451) and the Sticky Bottom (starts at line ~456).

Insert after the Medical Notes `.animate()` block:
```dart
const SizedBox(height: 16),

// -- Patient documents section --
if (_appointment.status == AppointmentStatus.confirmed ||
    _appointment.status == AppointmentStatus.completed)
  _sectionCard(
    isDark: isDark,
    child: // ... folder icon + "Patient Documents" label + description + arrow button
  ).animate(delay: 550.ms).fadeIn(duration: 400.ms),
```

The card contains:
- Left: folder icon in colored circle
- Center: "Patient Documents" title + "View and manage patient's medical documents" subtitle
- Right: chevron_right icon
- `onTap`: Navigate to `DoctorPatientDocumentsScreen` with:
  - `patientId: _appointment.patientId`
  - `patientName: _appointment.patientName`
  - `appointmentId: _appointment.id`
  - `doctorId: widget.doctor.userId` (auth UID, NOT doctor Firestore doc ID)
  - `doctorName: widget.doctor.name`
  - `isReadOnly: _appointment.status == AppointmentStatus.completed`

Add import for `DoctorPatientDocumentsScreen`.

---

### Phase 9 — Firestore Rules (EDIT)
**File:** `firestore.rules`

Add new helper + match block:

```
// Helper: check if user has doctor role
function isDoctor() {
  return isAuthenticated() &&
    get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'doctor';
}

// -- Medical Documents Collection --
match /medical_documents/{docId} {
  // Patient: full access to own documents
  allow read: if isAuthenticated() &&
    resource.data.userId == request.auth.uid;
  allow create: if isAuthenticated() &&
    request.resource.data.userId == request.auth.uid;

  // Doctor: read any patient's documents
  allow read: if isDoctor();

  // Doctor: create documents for patients (addedBy must be self)
  allow create: if isDoctor() &&
    request.resource.data.addedBy == request.auth.uid;

  // Anyone can update/delete only documents they added
  allow update, delete: if isAuthenticated() &&
    resource.data.addedBy == request.auth.uid;
}
```

---

## User Flows

### Doctor Flow
1. Doctor confirms appointment (existing QR/manual flow)
2. Status changes to `confirmed`
3. Appointment detail screen now shows **"Patient Documents"** card
4. Doctor taps -> opens `DoctorPatientDocumentsScreen` (full access)
5. Doctor sees all patient docs (view-only) + their own docs (edit/delete)
6. Doctor taps FAB -> add new document (medicine, prescription, etc.)
7. Doctor completes appointment -> status changes to `completed`
8. "Patient Documents" card stays visible -> opens in **read-only** mode

### Patient Flow
1. Patient navigates to Medical Documents (from profile screen)
2. Sees ALL documents: their own + doctor-added
3. Doctor-added docs show **"Added by Dr. X"** badge with date
4. Patient can **view** all docs
5. Patient can **edit/delete** only their OWN docs (doctor's docs have no edit/delete options)
6. Patient can upload new docs as before (attributed as "patient")

---

## Execution Order

```
Phase 1 (Model)  ──┐
Phase 2 (Repo)   ──┤── Data layer (no UI dependencies)
Phase 3 (Provider)──┘
        │
Phase 4 (main.dart) ── Register provider
        │
Phase 5 (L10n) ── Add keys + regenerate
        │
Phase 6 (Patient Screen) ──┐── UI layer (depends on provider + l10n)
Phase 7 (Doctor Screen)  ──┘
        │
Phase 8 (Detail Screen) ── Wire doctor screen into navigation
        │
Phase 9 (Firestore Rules) ── Security (can be done anytime)
```
