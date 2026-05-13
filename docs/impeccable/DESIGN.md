---
name: "University Health Center (UHC)"
description: "A multilingual Flutter healthcare appointment and management platform for university health centers."
colors:
  primary-clinical-blue: "#2196F3"
  primary-clinical-blue-light: "#64B5F6"
  primary-clinical-blue-dark: "#1976D2"
  secondary-care-teal: "#009688"
  secondary-care-teal-light: "#4DB6AC"
  secondary-care-teal-dark: "#00796B"
  tertiary-appointment-amber: "#FFB300"
  background-light: "#F5F7FA"
  background-dark: "#121212"
  surface-light: "#FFFFFF"
  surface-dark: "#1E1E1E"
  text-primary-light: "#212121"
  text-secondary-light: "#757575"
  text-primary-dark: "#E0E0E0"
  text-secondary-dark: "#9E9E9E"
  success: "#4CAF50"
  warning: "#FF9800"
  error: "#F44336"
  general-medicine: "#2196F3"
  dentistry: "#9C27B0"
  psychology: "#4CAF50"
  pharmacy: "#FF5722"
typography:
  display:
    fontFamily: "Poppins"
    fontSize: "57px"
    fontWeight: 400
    letterSpacing: "normal"
  headline:
    fontFamily: "Poppins"
    fontSize: "32px"
    fontWeight: 600
    letterSpacing: "normal"
  title:
    fontFamily: "Poppins"
    fontSize: "22px"
    fontWeight: 500
    letterSpacing: "normal"
  body:
    fontFamily: "Roboto"
    fontSize: "16px"
    fontWeight: 400
    letterSpacing: "normal"
  label:
    fontFamily: "Roboto"
    fontSize: "14px"
    fontWeight: 500
    letterSpacing: "normal"
rounded:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  dialog: "24px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  xxl: "24px"
components:
  button-primary:
    backgroundColor: "{colors.primary-clinical-blue}"
    textColor: "{colors.surface-light}"
    typography: "{typography.label}"
    rounded: "{rounded.lg}"
    height: "56px"
    width: "100%"
  button-outlined:
    backgroundColor: "transparent"
    textColor: "{colors.primary-clinical-blue}"
    typography: "{typography.label}"
    rounded: "{rounded.lg}"
    height: "56px"
    width: "100%"
  card:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.text-primary-light}"
    rounded: "{rounded.lg}"
    padding: "16px"
  input:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.text-primary-light}"
    rounded: "{rounded.lg}"
    padding: "20px 18px"
  chip:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.text-primary-light}"
    rounded: "{rounded.xl}"
---

# Design System: University Health Center (UHC)

## 1. Overview

**Creative North Star: "The Calm Clinical Console"**

UHC is a product interface for real healthcare workflows: booking, schedule management, QR check-in, user administration, reporting, and governance. Its visual system should feel calm and trustworthy first, then modern and polished. Every screen should help the user understand what is happening, what role they are acting in, and what action is safe to take next.

The app supports both light and dark mode as first-class experiences. Light mode should feel clean, approachable, and suitable for daily student and staff use. Dark mode should feel focused, comfortable, and equally complete for doctors, admins, and users who choose it in profile settings.

The system rejects generic hospital-template visuals, unserious playful styling, heavy corporate-gray admin density, and decorative effects that reduce scan speed. Gradients and glass treatments may exist, but only when they strengthen hierarchy or create a purposeful hero moment.

**Key Characteristics:**
- Role-aware, workflow-first screens for patients, doctors, admins, and super admins.
- Calm blue/teal healthcare identity with amber and status colors used for meaning.
- Soft Material 3 surfaces with rounded controls and restrained elevation.
- Consistent light/dark token pairs across shared Flutter widgets.
- Multilingual layouts that must survive English, Arabic, Kurdish, and RTL.

## 2. Colors

The palette is a Material 3 healthcare palette anchored in clinical blue, care teal, and clear status colors, with separate light and dark surfaces.

### Primary
- **Clinical Blue**: The main action and navigation color. Use for primary buttons, focused input borders, selected navigation items, links, active tabs, and important appointment actions.
- **Clinical Blue Light**: The dark-theme primary and selected-state color. Use where the base primary would lose contrast on dark surfaces.
- **Clinical Blue Dark**: The deeper gradient partner and contained primary color. Use for depth in major CTA gradients and stronger blue emphasis.

### Secondary
- **Care Teal**: A supporting healthcare accent. Use for secondary actions, department context, and positive clinical framing where it does not conflict with status green.
- **Care Teal Light / Dark**: Theme-aware secondary containers and gradients.

### Tertiary
- **Appointment Amber**: A caution and attention accent. Use sparingly for warnings, schedule notes, time-sensitive appointment context, and non-destructive alerts.

### Neutral
- **Light App Background**: A soft off-white app canvas for light mode.
- **Dark App Background**: A near-black app canvas for dark mode.
- **Light Surface / Dark Surface**: Card, input, dialog, and navigation surfaces.
- **Text Primary / Text Secondary**: Theme-paired text tokens. Use secondary text for metadata, hints, helper text, and lower-priority details.

### Named Rules

**The Meaning Before Decoration Rule.** Blue means primary action, teal means supportive care context, amber means attention, green means success, red means error or destructive action. Do not use these colors only because they look nice.

**The Two Theme Rule.** Every new color decision must be checked in light mode and dark mode. Dark mode is not optional or secondary.

## 3. Typography

**Display Font:** Poppins  
**Body Font:** Roboto  
**Label/Mono Font:** Roboto

**Character:** Poppins gives headings and section titles a modern, rounded confidence. Roboto keeps forms, body copy, labels, and dense admin content readable and familiar across Flutter surfaces.

### Hierarchy
- **Display** (400, 57px / 45px / 36px): Reserved for splash, onboarding, and rare high-emphasis empty or hero states.
- **Headline** (600, 32px / 28px / 24px): Use for screen titles, major dashboard headers, and dialog titles.
- **Title** (500, 22px / 16px / 14px): Use for cards, form sections, appointment summaries, and list item names.
- **Body** (400, 16px / 14px / 12px): Use for readable patient, doctor, admin, and settings content. Keep long prose to roughly 65-75 characters per line on wide layouts.
- **Label** (500, 14px / 12px / 11px): Use for buttons, chips, metadata, tabs, and compact controls.

### Named Rules

**The Scan First Rule.** In workflow screens, typography must help users scan names, dates, statuses, and actions before it tries to feel expressive.

## 4. Elevation

UHC uses a hybrid of flat Material surfaces, soft shadows, and tonal layering. Core theme cards are flat by default (`elevation: 0`), while shared widgets add subtle shadows for search fields, gradient cards, bottom navigation, dialogs, floating action buttons, and snackbars. Elevation should clarify hierarchy, not decorate every surface.

### Shadow Vocabulary
- **Soft Search Shadow** (`blur: 10px; offset: 0 2px; alpha: 0.05`): Use under search fields and lightweight floating controls.
- **Primary Button Glow** (`blur: 10px; offset: 0 5px; primary alpha: 0.30`): Use only for enabled primary gradient buttons.
- **Gradient Card Lift** (`blur: 20px; offset: 0 10px; first gradient color alpha: 0.30`): Use for hero cards and high-emphasis dashboard headers.
- **Dialog Elevation** (`elevation: 8`): Use for focused blocking decisions.
- **Floating Action Elevation** (`elevation: 4`): Use for floating action buttons.

### Named Rules

**The Flat Until Important Rule.** Default cards stay flat. Add lift only when a component needs to sit above the workflow or call attention to an action.

## 5. Components

### Buttons

- **Shape:** Soft rounded rectangle (16px radius).
- **Primary:** Full-width by default, 56px tall, Poppins 16px semibold, blue gradient from Clinical Blue to Clinical Blue Dark, white foreground, and a soft blue glow when enabled.
- **Loading:** Replace content with a 24px circular progress indicator. Do not resize the button during loading.
- **Outlined:** Transparent background, 2px Clinical Blue border, Clinical Blue text. In dark mode, use Clinical Blue Light where contrast requires it.
- **Disabled:** Use neutral gray and remove gradient glow.

### Chips

- **Style:** Rounded pill shape (20px radius), Roboto 14px, surface background by default.
- **State:** Selected chips use primary containers: Clinical Blue Light in light mode and Clinical Blue Dark in dark mode.

### Cards / Containers

- **Corner Style:** Standard cards use 16px radius. Gradient and glass cards use 20px radius. Dialogs use 24px radius.
- **Background:** Use Light Surface in light mode and Dark Surface in dark mode.
- **Shadow Strategy:** Flat by default; use documented soft shadows only for search, hero, dialog, FAB, and high-emphasis surfaces.
- **Internal Padding:** 16px for standard cards, 20px for hero or gradient cards.

### Inputs / Fields

- **Style:** Filled field with surface background, 16px radius, 20px horizontal and 18px vertical padding.
- **Default Border:** Light mode uses a pale gray stroke; dark mode uses a dark gray stroke.
- **Focus:** 2px Clinical Blue border in light mode; 2px Clinical Blue Light border in dark mode.
- **Error:** Red error border and Roboto 12px error text.
- **Labels:** Poppins 14px medium above the field with 8px spacing.

### Navigation

- **Bottom Navigation:** Fixed type with visible selected and unselected labels. Use surface background, primary selected item color, secondary text for unselected items, and elevation 8.
- **Tabs:** Poppins labels, 14px, selected label semibold and primary colored, unselected label medium and secondary colored.
- **App Bars:** Transparent, centered title, no elevation, theme-aware foreground.

### Loading States

- **Skeletons:** Use shimmer placeholders instead of blank spinners for lists and cards. Use 8px radius for generic lines, 16px for cards, and theme-aware gray ramps.

### Signature Components

- **Gradient Card:** Use for hero cards, dashboard greetings, and high-emphasis profile headers. Keep it rare.
- **Glassmorphic Card:** Use only when the background context makes blur meaningful. It is not the default card style.

## 6. Do's and Don'ts

### Do:

- **Do** preserve both light mode and dark mode for every shared widget and new screen.
- **Do** use `AppColors` and `AppTheme` tokens instead of hardcoded one-off colors.
- **Do** use Poppins for headings and Roboto for body, fields, labels, and dense content.
- **Do** communicate appointment and admin states with color, iconography, labels, and layout together.
- **Do** leave enough spacing for Arabic and Kurdish text, RTL layouts, and longer translated strings.
- **Do** keep critical healthcare and governance actions visually distinct from routine actions.

### Don't:

- **Don't** make UHC feel like a generic hospital template with only white, teal, and stock medical icons everywhere.
- **Don't** make patient, doctor, or admin workflows feel playful in a way that makes healthcare decisions unserious.
- **Don't** make admin screens feel like a heavy corporate gray system with dense tables and no warmth.
- **Don't** use decorative glass, gradients, or effects when they reduce scan speed, readability, or confidence.
- **Don't** add new colors that work in only one theme.
- **Don't** use color alone to communicate appointment status, permissions, errors, or destructive actions.
