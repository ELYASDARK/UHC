# Doctor Screen Implementation Plan

## Project Context

**App:** UHC (University Health Center) - Flutter mobile app  
**Target Role:** `UserRole.doctor`  
**Current State:** The app currently has a patient-oriented UI. Doctors exist in the data model (`DoctorModel` in Firestore `doctors` collection, linked to `UserModel` via `userId`), but there are **no doctor-facing screens**. All authenticated users are routed to the patient `MainShell` regardless of role.

---

## Overview

Build a complete doctor experience that is shown when a user with `role: doctor` logs in. The doctor gets a **separate navigation shell** with 5 tabs: Dashboard, Appointments, Schedule, Notifications, and Profile. The three core features are:

1. **View Scheduled Appointments** - See and manage patient appointments
2. **Manage Availability and Schedule** - Toggle availability on/off
3. **Patient Information Access** - View patient profiles and appointment history

---

## Architecture Decisions

| Decision | Choice |
|---|---|
| Navigation | Separate `DoctorShell` (not shared with patient `MainShell`) |
| Bottom tabs | 5 tabs: Dashboard, Appointments, Schedule, Notifications, Profile |
| Appointment actions | Full status management (confirm, complete, cancel, no-show) + admin can also manage |
| Medical notes | Doctor can write notes; visible to doctor and admin only, **not** to patients |
| Schedule control | Toggle overall availability on/off only (detailed schedule managed by admin) |
| Patient info depth | Patient profile + appointment history with this specific doctor |
| Doctor profile | Self-service editing (bio, specialization, qualifications, photo) |
| Notifications | Push notifications for new bookings, cancellations, and reschedules |

---

## Phase 1: Role-Based Routing

### 1.1 Update `AppNavigator` in `main.dart`

- After authentication, check `authProvider.currentUser.role`
- If `UserRole.doctor` -> route to `DoctorShell`
- If `UserRole.admin` -> route to existing `MainShell` (or admin shell if built later)
- Otherwise -> route to existing patient `MainShell`
- The doctor's `DoctorModel` must be fetched using the `userId` from the authenticated `UserModel`

### 1.2 Create `DoctorShell` widget

- **File:** `lib/screens/doctor/doctor_shell.dart`
- `IndexedStack` with 5 tabs (same pattern as existing `MainShell`)
- Bottom navigation bar with tabs:
  1. **Dashboard** (icon: `dashboard`)
  2. **Appointments** (icon: `calendar_today`)
  3. **Schedule** (icon: `schedule`)
  4. **Notifications** (icon: `notifications`)
  5. **Profile** (icon: `person`)

### 1.3 Create `DoctorAppointmentProvider`

- **File:** `lib/providers/doctor_appointment_provider.dart`
- Loads appointments by `doctorId` (not `patientId` like the existing `AppointmentProvider`)
- Methods: `loadTodayAppointments()`, `loadAppointmentsByDate(date)`, `loadUpcomingAppointments()`, `loadPastAppointments()`
- Uses existing `AppointmentRepository.getDoctorAppointments(doctorId, date)`
- Add methods: `confirmAppointment(id)`, `completeAppointment(id)`, `cancelAppointment(id, reason)`, `markNoShow(id)`

---

## Phase 2: Dashboard (Home Tab)

### 2.1 Doctor Dashboard Screen

- **File:** `lib/screens/doctor/doctor_dashboard_screen.dart`
- **Today-focused layout:**
  - **Greeting header:** "Good morning, Dr. [Name]" with current date
  - **Quick stats row** (cards):
    - Total patients today
    - Pending appointments
    - Completed appointments
    - Cancelled/no-show count
  - **Next upcoming appointment** (prominent card):
    - Patient name, time, appointment type
    - Quick action buttons (confirm, start, etc.)
  - **Today's appointment list** (scrollable):
    - Each item shows: time, patient name, type, status badge
    - Tap to open appointment detail
  - **Availability toggle:** Quick on/off switch for `isAvailable`

---

## Phase 3: Appointments Tab

### 3.1 Doctor Appointments Screen

- **File:** `lib/screens/doctor/doctor_appointments_screen.dart`
- **Two sub-tabs:** Upcoming | Past
- **Upcoming tab:**
  - Date filter/picker at top
  - List of appointments sorted by time
  - Each card shows: patient name, time, type, status
  - Status badge colors: pending (orange), confirmed (blue), completed (green), cancelled (red), no-show (grey)
- **Past tab:**
  - Similar list but for completed/cancelled/no-show appointments
  - Includes medical notes preview if written

### 3.2 Doctor Appointment Detail Screen

- **File:** `lib/screens/doctor/doctor_appointment_detail_screen.dart`
- **Appointment info section:**
  - Date, time, type, status, booking reference
  - QR code display (existing field in `AppointmentModel`)
- **Patient info section:**
  - Name, email, phone (tap to call), date of birth, blood type, allergies
  - Link to full patient profile
- **Action buttons** (based on current status):
  - Pending -> Confirm / Cancel
  - Confirmed -> Mark Completed / Mark No-Show / Cancel
  - Completed -> (read-only, show notes)
- **Medical notes section:**
  - Text field for doctor to write consultation/medical notes
  - Save button
  - Notes are stored in `AppointmentModel.medicalNotes`
  - **Visibility: doctor and admin only** (patient cannot see these notes)
- **Appointment history link:** View past appointments with this patient

### 3.3 Update `AppointmentModel` (if needed)

- Ensure `medicalNotes` field exists (it does in current model)
- Add `medicalNotesUpdatedAt` timestamp field if not present
- Add `statusUpdatedBy` field to track who changed the status (doctor vs admin)

---

## Phase 4: Schedule Tab

### 4.1 Doctor Schedule Screen

- **File:** `lib/screens/doctor/doctor_schedule_screen.dart`
- **Weekly view** showing the doctor's current schedule (read from `DoctorModel.weeklySchedule`)
- For each day: list of time slots with availability status
- **Overall availability toggle** at the top:
  - Maps to `DoctorModel.isAvailable`
  - When toggled OFF: all slots show as unavailable to patients, no new bookings allowed
  - When toggled ON: slots follow the admin-configured schedule
- Visual indicator showing which slots are booked vs. available vs. blocked
- **Note/banner:** "Contact admin to modify your schedule" (since detailed editing is admin-only)

### 4.2 Update `DoctorRepository`

- Add method: `updateDoctorAvailability(doctorId, bool isAvailable)`
- This updates the `isAvailable` field in the `doctors` Firestore collection

---

## Phase 5: Patient Information Access

### 5.1 Patient Detail Screen (Doctor View)

- **File:** `lib/screens/doctor/patient_detail_screen.dart`
- **Patient profile section:**
  - Name, email, phone, date of birth, blood type, allergies
  - Profile photo
- **Appointment history section:**
  - List of all past appointments **with this specific doctor only**
  - Each entry shows: date, type, status, medical notes preview
  - Tap to view full appointment detail
- **Accessed from:** Doctor Appointment Detail Screen -> "View Patient Profile" link

### 5.2 Patient Repository Updates

- Add method to `AppointmentRepository`: `getPatientAppointmentsWithDoctor(patientId, doctorId)`
- Returns all appointments between a specific patient and doctor, sorted by date descending

---

## Phase 6: Doctor Profile Tab

### 6.1 Doctor Profile Screen

- **File:** `lib/screens/doctor/doctor_profile_screen.dart`
- **Profile display:**
  - Photo, name, email, department, specialization
  - Bio, experience years, qualifications list
  - Availability status badge
- **Action buttons:**
  - Edit Profile
  - Change Password (reuse existing `ChangePasswordScreen`)
  - Notification Settings (reuse existing `NotificationSettingsScreen`)
  - Sign Out
- **Settings section:**
  - Theme toggle (reuse existing)
  - Language selector (reuse existing)

### 6.2 Edit Doctor Profile Screen

- **File:** `lib/screens/doctor/edit_doctor_profile_screen.dart`
- **Editable fields:**
  - Profile photo (camera/gallery picker)
  - Bio (multiline text)
  - Specialization
  - Experience years
  - Qualifications (add/remove list)
- **Non-editable fields** (shown but greyed out, managed by admin):
  - Name, email, department
- Saves to both `DoctorModel` (doctor-specific fields) and `UserModel` (photo, etc.)

---

## Phase 7: Notifications

### 7.1 Doctor Notification Types

Add the following notification triggers (via Cloud Functions or FCM topics):

| Event | Notification to Doctor |
|---|---|
| Patient books appointment | "New appointment: [Patient] on [Date] at [Time]" |
| Patient cancels appointment | "[Patient] cancelled their [Date] appointment" |
| Patient reschedules | "[Patient] rescheduled from [OldDate] to [NewDate]" |
| Upcoming appointment (1h before) | "Upcoming: [Patient] in 1 hour" |

### 7.2 Doctor Notifications Screen

- **File:** `lib/screens/doctor/doctor_notifications_screen.dart`
- Reuse the existing `NotificationsScreen` pattern/UI
- Filter notifications by doctor's `userId`
- Mark as read, delete functionality

---

## File Structure Summary

```
lib/
  screens/
    doctor/
      doctor_shell.dart                    # Main navigation shell (5 tabs)
      doctor_dashboard_screen.dart         # Tab 1: Today-focused dashboard
      doctor_appointments_screen.dart      # Tab 2: Upcoming/Past appointments
      doctor_appointment_detail_screen.dart # Appointment detail + actions + notes
      doctor_schedule_screen.dart          # Tab 3: Weekly schedule + availability toggle
      doctor_notifications_screen.dart     # Tab 4: Doctor notifications
      doctor_profile_screen.dart           # Tab 5: Profile display
      edit_doctor_profile_screen.dart      # Edit doctor profile
      patient_detail_screen.dart           # Patient info + history with this doctor
  providers/
    doctor_appointment_provider.dart       # Doctor's appointment state management
```

---

## Existing Code to Reuse

| What | Where | How |
|---|---|---|
| `DoctorModel` + `TimeSlot` | `lib/data/models/doctor_model.dart` | Already has schedule, availability, all needed fields |
| `AppointmentModel` | `lib/data/models/appointment_model.dart` | Already has `medicalNotes`, `status`, all needed fields |
| `AppointmentRepository.getDoctorAppointments()` | `lib/data/repositories/appointment_repository.dart` | Already supports querying by doctorId |
| `DoctorRepository` | `lib/data/repositories/doctor_repository.dart` | Already has CRUD, just needs `updateAvailability` |
| `ChangePasswordScreen` | `lib/screens/profile/change_password_screen.dart` | Reuse directly |
| `NotificationSettingsScreen` | `lib/screens/settings/notification_settings_screen.dart` | Reuse directly |
| Theme/Locale providers | `lib/providers/theme_provider.dart`, `locale_provider.dart` | Already global, works in any shell |
| `AppColors`, `AppTheme` | `lib/core/` | Reuse for consistent styling |

---

## Firestore Security Rules Updates

Add rules to ensure:
- Doctors can only read appointments where `doctorId` matches their doctor document ID
- Doctors can update appointment `status` and `medicalNotes` fields only
- Doctors can update their own `DoctorModel` fields: `bio`, `specialization`, `experienceYears`, `qualifications`, `isAvailable`, `photoUrl`
- Doctors cannot modify `departmentId`, `name`, `email`, `isActive`, or `weeklySchedule`
- `medicalNotes` field is NOT readable by the patient (only by doctor and admin roles)

---

## Implementation Order (Recommended)

1. **Phase 1** - Role-based routing + DoctorShell (foundation, everything depends on this)
2. **Phase 3** - Appointments tab + detail screen (core feature, most complex)
3. **Phase 2** - Dashboard (depends on appointment data loading from Phase 3)
4. **Phase 5** - Patient info access (extends appointment detail from Phase 3)
5. **Phase 4** - Schedule tab (simpler, toggle only)
6. **Phase 6** - Doctor profile (least complex, mostly reuses existing patterns)
7. **Phase 7** - Notifications (requires Cloud Functions work, can be done in parallel)

---

## Out of Scope (Not in This Plan)

- Doctor-to-patient messaging/chat
- Video consultation
- Prescription management
- Lab results viewing
- Doctor analytics/reports dashboard
- Multi-doctor clinic management
- Calendar integration (Google Calendar, etc.)
