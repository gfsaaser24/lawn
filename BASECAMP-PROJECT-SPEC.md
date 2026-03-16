# PROJECT SPEC: Client Management System (CMS)

## Codename: **BASECAMP**

**Version:** 0.1.0-draft
**Author:** Gabe Fletcher / Detailing Growth
**Date:** March 12, 2026
**Baseline Reference:** [pingdotgg/lawn](https://github.com/pingdotgg/lawn) (video.lawn)

---

## 1. Executive Summary

Basecamp is an internal client management system for Detailing Growth and its portfolio companies. It provides a **staff-side operational hub** and a **client-facing portal** — both running inside a single application with role-gated routing and shared data infrastructure.

The staff side is where agency operators live: AI chat, image/video generation, MCP tool orchestration, file management, client profiles, onboarding workflows, social media management, call transcription, and process automation. The client side is a white-labeled portal where clients manage their projects, review video deliverables, receive notifications, and collaborate through comments.

The system is built on the same stack as lawn (video.lawn) — a proven, shipping codebase — but extends its data model, auth system, and feature surface significantly.

---

## 2. Technical Stack (Inherited from lawn)

### 2.1 Core Runtime & Build

| Layer | Technology | Notes |
|---|---|---|
| **Package Manager** | npm 10+ | `npm install`, `npm run dev` |
| **Build Tool** | Vite 7+ | With `@vitejs/plugin-react` |
| **Framework** | TanStack Start (React) | SPA mode with prerendered marketing pages |
| **Router** | TanStack Router | File-based routing under `app/routes/` |
| **Language** | TypeScript 5+ | Strict mode, shared types across client/server |

### 2.2 Backend & Data

| Layer | Technology | Notes |
|---|---|---|
| **Database / Backend** | Convex | Reactive queries, mutations, actions, scheduled jobs |
| **Auth** | Clerk (via `@clerk/tanstack-react-start`) | JWT identity, Clerk user IDs as foreign keys |
| **File Storage** | AWS S3 (via `@aws-sdk/client-s3`) | Presigned upload/download URLs |
| **Video Processing** | Mux (`@mux/mux-node`) | Upload, transcode, HLS playback |
| **Payments** | Stripe (`@convex-dev/stripe`) | Subscriptions, billing status |

### 2.3 Frontend UI

| Layer | Technology | Notes |
|---|---|---|
| **UI Framework** | React 19 | Concurrent features, server components future-ready |
| **Styling** | Tailwind CSS 4 + PostCSS | Utility-first, no CSS-in-JS |
| **Component Primitives** | Radix UI | Dialog, Dropdown, Tabs, Avatar, Tooltip, etc. |
| **Utilities** | `clsx`, `tailwind-merge`, `class-variance-authority` | Component variant composition |
| **Icons** | Lucide React | Consistent icon set |
| **Video Playback** | Video.js + HLS.js | Adaptive streaming |

### 2.4 Convex Components (from lawn)

| Component | Purpose |
|---|---|
| `@convex-dev/presence` | Real-time user presence (who's viewing what) |
| `@convex-dev/rate-limiter` | API rate limiting |
| `@convex-dev/stripe` | Stripe webhook handling and subscription sync |

### 2.5 Additional Dependencies (New for Basecamp)

| Dependency | Purpose |
|---|---|
| Anthropic SDK / AI SDK | AI chat (Claude), structured outputs |
| Google Gemini API | Image generation |
| MCP Client SDK | Tool orchestration (external services) |
| Deepgram / AssemblyAI | Call transcription |
| Buffer / Ayrshare / custom | Social media management integration |
| `nanoid` (already in lawn) | Public ID generation |

---

## 3. Architecture Overview

### 3.1 Application Zones

The application has three distinct zones, all served from the same Vite/TanStack deployment:

```
/                        → Marketing / landing pages (prerendered)
/app/[teamSlug]/...      → Staff dashboard (auth required, staff roles)
/portal/[clientSlug]/... → Client portal (auth required, client role)
/share/[token]           → Public share links (no auth, token-gated)
```

### 3.2 Auth Model (Extended from lawn)

Lawn's existing auth model provides team membership with role hierarchy:

```
owner (4) > admin (3) > member (2) > viewer (1)
```

Basecamp extends this with a **dual-context** role system:

**Staff Roles** (internal team members):
- `owner` — Full system access, billing, RBAC management
- `admin` — All operational access, can manage staff and clients
- `member` — Standard operator: can manage assigned clients, use all tools
- `viewer` — Read-only access to dashboards and reports

**Client Roles** (external portal users):
- `client_admin` — Primary client contact, manages their own team members
- `client_member` — Can view projects, comment, upload files
- `client_viewer` — View-only access to project deliverables

The `requireTeamAccess()` pattern from lawn's `convex/auth.ts` is preserved and extended with a `requireClientAccess()` companion that checks client-scoped permissions.

### 3.3 Data Flow

```
┌─────────────────────────────┐
│  TanStack Start (Vite SPA)  │
│  React 19 + TanStack Router │
├─────────────────────────────┤
│         Convex Client        │  ← Reactive subscriptions
├─────────────────────────────┤
│       Convex Backend         │  ← Mutations, Actions, Scheduled Jobs
│  ┌─────┐ ┌─────┐ ┌───────┐  │
│  │Auth │ │Store│ │Actions│  │
│  │Clerk│ │ DB  │ │  S3   │  │
│  │     │ │     │ │  Mux  │  │
│  │     │ │     │ │  AI   │  │
│  │     │ │     │ │  MCP  │  │
│  └─────┘ └─────┘ └───────┘  │
└─────────────────────────────┘
```

---

## 4. Convex Schema (Full Data Model)

This extends lawn's schema. Tables marked **[LAWN]** are carried over (with modifications noted). Tables marked **[NEW]** are additions.

```typescript
import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({

  // ═══════════════════════════════════════════════
  // TEAM & AUTH (extended from lawn)
  // ═══════════════════════════════════════════════

  // [LAWN] Teams — the staff organization
  teams: defineTable({
    name: v.string(),
    slug: v.string(),
    ownerClerkId: v.string(),
    plan: v.union(
      v.literal("free"),
      v.literal("basic"),
      v.literal("pro"),
      v.literal("team"),
      v.literal("enterprise")
    ),
    stripeCustomerId: v.optional(v.string()),
    stripeSubscriptionId: v.optional(v.string()),
    stripePriceId: v.optional(v.string()),
    billingStatus: v.optional(v.string()),
    // NEW: branding
    logoUrl: v.optional(v.string()),
    brandColor: v.optional(v.string()),
  })
    .index("by_slug", ["slug"])
    .index("by_owner", ["ownerClerkId"])
    .index("by_stripe_customer_id", ["stripeCustomerId"])
    .index("by_stripe_subscription_id", ["stripeSubscriptionId"]),

  // [LAWN] Team members — staff users
  teamMembers: defineTable({
    teamId: v.id("teams"),
    userClerkId: v.string(),
    userEmail: v.string(),
    userName: v.string(),
    userAvatarUrl: v.optional(v.string()),
    role: v.union(
      v.literal("owner"),
      v.literal("admin"),
      v.literal("member"),
      v.literal("viewer")
    ),
  })
    .index("by_team", ["teamId"])
    .index("by_user", ["userClerkId"])
    .index("by_team_and_user", ["teamId", "userClerkId"])
    .index("by_team_and_email", ["teamId", "userEmail"]),

  // [LAWN] Team invites
  teamInvites: defineTable({
    teamId: v.id("teams"),
    email: v.string(),
    role: v.union(
      v.literal("admin"),
      v.literal("member"),
      v.literal("viewer")
    ),
    invitedByClerkId: v.string(),
    invitedByName: v.string(),
    token: v.string(),
    expiresAt: v.number(),
  })
    .index("by_team", ["teamId"])
    .index("by_email", ["email"])
    .index("by_token", ["token"]),


  // ═══════════════════════════════════════════════
  // CLIENT MANAGEMENT
  // ═══════════════════════════════════════════════

  // [NEW] Client profiles — the businesses we serve
  clients: defineTable({
    teamId: v.id("teams"),
    name: v.string(),                          // Business name
    slug: v.string(),                          // URL slug
    contactName: v.string(),
    contactEmail: v.string(),
    contactPhone: v.optional(v.string()),
    address: v.optional(v.string()),
    website: v.optional(v.string()),
    industry: v.optional(v.string()),          // e.g. "PPF", "Ceramic Coating", "Tint"
    status: v.union(
      v.literal("lead"),
      v.literal("onboarding"),
      v.literal("active"),
      v.literal("paused"),
      v.literal("churned")
    ),
    onboardedAt: v.optional(v.number()),
    notes: v.optional(v.string()),
    // Billing / plan
    monthlyRetainer: v.optional(v.number()),
    stripeCustomerId: v.optional(v.string()),
    // Metadata
    avatarUrl: v.optional(v.string()),
    tags: v.optional(v.array(v.string())),
  })
    .index("by_team", ["teamId"])
    .index("by_team_and_slug", ["teamId", "slug"])
    .index("by_team_and_status", ["teamId", "status"])
    .index("by_stripe_customer_id", ["stripeCustomerId"]),

  // [NEW] Client portal users — external users who log into the client portal
  clientMembers: defineTable({
    clientId: v.id("clients"),
    userClerkId: v.string(),
    userEmail: v.string(),
    userName: v.string(),
    userAvatarUrl: v.optional(v.string()),
    role: v.union(
      v.literal("client_admin"),
      v.literal("client_member"),
      v.literal("client_viewer")
    ),
  })
    .index("by_client", ["clientId"])
    .index("by_user", ["userClerkId"])
    .index("by_client_and_user", ["clientId", "userClerkId"]),

  // [NEW] Client invites
  clientInvites: defineTable({
    clientId: v.id("clients"),
    email: v.string(),
    role: v.union(
      v.literal("client_admin"),
      v.literal("client_member"),
      v.literal("client_viewer")
    ),
    invitedByClerkId: v.string(),
    invitedByName: v.string(),
    token: v.string(),
    expiresAt: v.number(),
  })
    .index("by_client", ["clientId"])
    .index("by_email", ["email"])
    .index("by_token", ["token"]),

  // [NEW] Client onboarding checklists
  onboardingChecklists: defineTable({
    clientId: v.id("clients"),
    templateId: v.optional(v.string()),
    steps: v.array(v.object({
      id: v.string(),
      label: v.string(),
      completed: v.boolean(),
      completedAt: v.optional(v.number()),
      completedByClerkId: v.optional(v.string()),
      notes: v.optional(v.string()),
    })),
  })
    .index("by_client", ["clientId"]),


  // ═══════════════════════════════════════════════
  // PROJECTS & DELIVERABLES
  // ═══════════════════════════════════════════════

  // [LAWN — modified] Projects — now scoped to clients
  projects: defineTable({
    teamId: v.id("teams"),
    clientId: v.optional(v.id("clients")),     // NEW: client association
    name: v.string(),
    description: v.optional(v.string()),
    status: v.union(                           // NEW: project lifecycle
      v.literal("planning"),
      v.literal("in_progress"),
      v.literal("review"),
      v.literal("completed"),
      v.literal("archived")
    ),
    dueDate: v.optional(v.number()),
    clientVisible: v.boolean(),                // NEW: show in client portal
  })
    .index("by_team", ["teamId"])
    .index("by_client", ["clientId"])
    .index("by_team_and_status", ["teamId", "status"]),

  // [LAWN — preserved] Videos
  videos: defineTable({
    projectId: v.id("projects"),
    uploadedByClerkId: v.string(),
    uploaderName: v.string(),
    title: v.string(),
    description: v.optional(v.string()),
    visibility: v.union(v.literal("public"), v.literal("private")),
    publicId: v.string(),
    muxUploadId: v.optional(v.string()),
    muxAssetId: v.optional(v.string()),
    muxPlaybackId: v.optional(v.string()),
    muxAssetStatus: v.optional(
      v.union(
        v.literal("preparing"),
        v.literal("ready"),
        v.literal("errored")
      )
    ),
    s3Key: v.optional(v.string()),
    duration: v.optional(v.number()),
    thumbnailUrl: v.optional(v.string()),
    fileSize: v.optional(v.number()),
    contentType: v.optional(v.string()),
    uploadError: v.optional(v.string()),
    status: v.union(
      v.literal("uploading"),
      v.literal("processing"),
      v.literal("ready"),
      v.literal("failed")
    ),
    workflowStatus: v.union(
      v.literal("review"),
      v.literal("rework"),
      v.literal("done")
    ),
    clientVisible: v.boolean(),                // NEW: visible in client portal
  })
    .index("by_project", ["projectId"])
    .index("by_public_id", ["publicId"])
    .index("by_mux_upload_id", ["muxUploadId"])
    .index("by_mux_asset_id", ["muxAssetId"])
    .index("by_mux_playback_id", ["muxPlaybackId"]),

  // [LAWN — preserved] Comments
  comments: defineTable({
    videoId: v.id("videos"),
    userClerkId: v.string(),
    userName: v.string(),
    userAvatarUrl: v.optional(v.string()),
    text: v.string(),
    timestampSeconds: v.number(),
    parentId: v.optional(v.id("comments")),
    resolved: v.boolean(),
    isClientComment: v.boolean(),              // NEW: flag for client-originated comments
  })
    .index("by_video", ["videoId"])
    .index("by_video_and_timestamp", ["videoId", "timestampSeconds"])
    .index("by_parent", ["parentId"]),

  // [LAWN — preserved] Share links
  shareLinks: defineTable({
    videoId: v.id("videos"),
    token: v.string(),
    createdByClerkId: v.string(),
    createdByName: v.string(),
    expiresAt: v.optional(v.number()),
    allowDownload: v.boolean(),
    password: v.optional(v.string()),
    passwordHash: v.optional(v.string()),
    failedAccessAttempts: v.optional(v.number()),
    lockedUntil: v.optional(v.number()),
    viewCount: v.number(),
  })
    .index("by_token", ["token"])
    .index("by_video", ["videoId"]),

  // [LAWN — preserved] Share access grants
  shareAccessGrants: defineTable({
    shareLinkId: v.id("shareLinks"),
    token: v.string(),
    expiresAt: v.number(),
    createdAt: v.number(),
  })
    .index("by_token", ["token"])
    .index("by_share_link", ["shareLinkId"]),


  // ═══════════════════════════════════════════════
  // FILE MANAGEMENT
  // ═══════════════════════════════════════════════

  // [NEW] Files — general file attachments (not just video)
  files: defineTable({
    teamId: v.id("teams"),
    clientId: v.optional(v.id("clients")),
    projectId: v.optional(v.id("projects")),
    uploadedByClerkId: v.string(),
    uploaderName: v.string(),
    fileName: v.string(),
    fileType: v.string(),                      // MIME type
    fileSize: v.number(),
    s3Key: v.string(),
    downloadUrl: v.optional(v.string()),
    tags: v.optional(v.array(v.string())),
    clientVisible: v.boolean(),
  })
    .index("by_team", ["teamId"])
    .index("by_client", ["clientId"])
    .index("by_project", ["projectId"]),


  // ═══════════════════════════════════════════════
  // AI & CHAT
  // ═══════════════════════════════════════════════

  // [NEW] AI chat conversations
  aiConversations: defineTable({
    teamId: v.id("teams"),
    userClerkId: v.string(),
    title: v.optional(v.string()),
    clientId: v.optional(v.id("clients")),     // Optionally scoped to a client
    model: v.string(),                         // "claude-sonnet-4", "gemini-2.0-flash", etc.
    systemPrompt: v.optional(v.string()),
  })
    .index("by_team", ["teamId"])
    .index("by_user", ["userClerkId"])
    .index("by_client", ["clientId"]),

  // [NEW] AI chat messages
  aiMessages: defineTable({
    conversationId: v.id("aiConversations"),
    role: v.union(
      v.literal("user"),
      v.literal("assistant"),
      v.literal("system"),
      v.literal("tool")
    ),
    content: v.string(),
    toolCalls: v.optional(v.any()),            // MCP tool call results
    metadata: v.optional(v.any()),             // Token usage, model info, etc.
  })
    .index("by_conversation", ["conversationId"]),

  // [NEW] AI generated images
  aiImages: defineTable({
    teamId: v.id("teams"),
    clientId: v.optional(v.id("clients")),
    generatedByClerkId: v.string(),
    prompt: v.string(),
    model: v.string(),                         // "gemini-2.0-flash", "imagen-3", etc.
    s3Key: v.string(),
    thumbnailUrl: v.optional(v.string()),
    width: v.optional(v.number()),
    height: v.optional(v.number()),
  })
    .index("by_team", ["teamId"])
    .index("by_client", ["clientId"]),


  // ═══════════════════════════════════════════════
  // MCP TOOL ORCHESTRATION
  // ═══════════════════════════════════════════════

  // [NEW] Registered MCP servers
  mcpServers: defineTable({
    teamId: v.id("teams"),
    name: v.string(),
    url: v.string(),
    description: v.optional(v.string()),
    enabled: v.boolean(),
    authConfig: v.optional(v.any()),           // Encrypted auth tokens/keys
  })
    .index("by_team", ["teamId"]),

  // [NEW] MCP tool execution log
  mcpExecutionLog: defineTable({
    teamId: v.id("teams"),
    serverId: v.id("mcpServers"),
    toolName: v.string(),
    input: v.any(),
    output: v.optional(v.any()),
    status: v.union(
      v.literal("pending"),
      v.literal("success"),
      v.literal("error")
    ),
    executedByClerkId: v.string(),
    durationMs: v.optional(v.number()),
    errorMessage: v.optional(v.string()),
  })
    .index("by_team", ["teamId"])
    .index("by_server", ["serverId"]),


  // ═══════════════════════════════════════════════
  // WORKFLOWS & PROCESSES
  // ═══════════════════════════════════════════════

  // [NEW] Workflow templates
  workflowTemplates: defineTable({
    teamId: v.id("teams"),
    name: v.string(),
    description: v.optional(v.string()),
    steps: v.array(v.object({
      id: v.string(),
      name: v.string(),
      type: v.union(
        v.literal("manual"),
        v.literal("approval"),
        v.literal("ai_action"),
        v.literal("mcp_tool"),
        v.literal("notification")
      ),
      config: v.optional(v.any()),
      order: v.number(),
    })),
    isActive: v.boolean(),
  })
    .index("by_team", ["teamId"]),

  // [NEW] Workflow instances (running workflows)
  workflowInstances: defineTable({
    templateId: v.id("workflowTemplates"),
    clientId: v.optional(v.id("clients")),
    projectId: v.optional(v.id("projects")),
    currentStepId: v.string(),
    status: v.union(
      v.literal("running"),
      v.literal("paused"),
      v.literal("completed"),
      v.literal("failed")
    ),
    stepHistory: v.array(v.object({
      stepId: v.string(),
      completedAt: v.number(),
      completedByClerkId: v.optional(v.string()),
      notes: v.optional(v.string()),
    })),
    startedAt: v.number(),
    completedAt: v.optional(v.number()),
  })
    .index("by_template", ["templateId"])
    .index("by_client", ["clientId"])
    .index("by_project", ["projectId"]),


  // ═══════════════════════════════════════════════
  // SOCIAL MEDIA MANAGEMENT
  // ═══════════════════════════════════════════════

  // [NEW] Social accounts linked per client
  socialAccounts: defineTable({
    clientId: v.id("clients"),
    platform: v.union(
      v.literal("instagram"),
      v.literal("facebook"),
      v.literal("tiktok"),
      v.literal("youtube"),
      v.literal("google_business"),
      v.literal("x")
    ),
    accountName: v.string(),
    accountId: v.optional(v.string()),
    accessToken: v.optional(v.string()),       // Encrypted
    refreshToken: v.optional(v.string()),      // Encrypted
    tokenExpiresAt: v.optional(v.number()),
    isConnected: v.boolean(),
  })
    .index("by_client", ["clientId"])
    .index("by_client_and_platform", ["clientId", "platform"]),

  // [NEW] Scheduled social posts
  socialPosts: defineTable({
    teamId: v.id("teams"),
    clientId: v.id("clients"),
    socialAccountId: v.id("socialAccounts"),
    content: v.string(),
    mediaUrls: v.optional(v.array(v.string())),
    scheduledAt: v.optional(v.number()),
    publishedAt: v.optional(v.number()),
    status: v.union(
      v.literal("draft"),
      v.literal("scheduled"),
      v.literal("published"),
      v.literal("failed")
    ),
    externalPostId: v.optional(v.string()),
    createdByClerkId: v.string(),
    errorMessage: v.optional(v.string()),
  })
    .index("by_client", ["clientId"])
    .index("by_status", ["status"])
    .index("by_scheduled_at", ["scheduledAt"]),


  // ═══════════════════════════════════════════════
  // CALL TRANSCRIPTION & RECORDINGS
  // ═══════════════════════════════════════════════

  // [NEW] Call recordings with transcriptions
  callRecordings: defineTable({
    teamId: v.id("teams"),
    clientId: v.id("clients"),
    title: v.string(),
    recordingS3Key: v.string(),
    duration: v.optional(v.number()),
    transcription: v.optional(v.string()),
    transcriptionStatus: v.union(
      v.literal("pending"),
      v.literal("processing"),
      v.literal("completed"),
      v.literal("failed")
    ),
    summary: v.optional(v.string()),           // AI-generated summary
    actionItems: v.optional(v.array(v.string())),
    uploadedByClerkId: v.string(),
    callDate: v.optional(v.number()),
  })
    .index("by_client", ["clientId"])
    .index("by_team", ["teamId"]),


  // ═══════════════════════════════════════════════
  // NOTIFICATIONS
  // ═══════════════════════════════════════════════

  // [NEW] Notifications (staff and client)
  notifications: defineTable({
    recipientClerkId: v.string(),
    type: v.union(
      v.literal("comment"),
      v.literal("video_ready"),
      v.literal("project_update"),
      v.literal("workflow_step"),
      v.literal("file_uploaded"),
      v.literal("mention"),
      v.literal("system")
    ),
    title: v.string(),
    body: v.optional(v.string()),
    linkUrl: v.optional(v.string()),
    read: v.boolean(),
    readAt: v.optional(v.number()),
    // Reference IDs
    clientId: v.optional(v.id("clients")),
    projectId: v.optional(v.id("projects")),
    videoId: v.optional(v.id("videos")),
  })
    .index("by_recipient", ["recipientClerkId"])
    .index("by_recipient_and_read", ["recipientClerkId", "read"]),


  // ═══════════════════════════════════════════════
  // ADMIN & AUDIT
  // ═══════════════════════════════════════════════

  // [NEW] RBAC permissions (granular)
  permissions: defineTable({
    teamId: v.id("teams"),
    role: v.string(),
    resource: v.string(),                      // e.g. "clients", "ai_chat", "billing"
    actions: v.array(v.string()),              // e.g. ["read", "write", "delete"]
  })
    .index("by_team_and_role", ["teamId", "role"]),

  // [NEW] Audit log
  auditLog: defineTable({
    teamId: v.id("teams"),
    actorClerkId: v.string(),
    actorName: v.string(),
    action: v.string(),                        // e.g. "client.created", "video.uploaded"
    resourceType: v.string(),
    resourceId: v.optional(v.string()),
    metadata: v.optional(v.any()),
    ipAddress: v.optional(v.string()),
  })
    .index("by_team", ["teamId"])
    .index("by_actor", ["actorClerkId"]),
});
```

---

## 5. Route Structure

### 5.1 Marketing (Prerendered)

```
/                           → Landing page
/pricing                    → Pricing / plans
/login                      → Clerk sign-in
/signup                     → Clerk sign-up
```

### 5.2 Staff Dashboard (`/app`)

```
/app                              → Team selector / dashboard home
/app/[teamSlug]                   → Team overview (client list, KPIs)
/app/[teamSlug]/clients           → All clients list
/app/[teamSlug]/clients/new       → New client onboarding form
/app/[teamSlug]/clients/[clientSlug]           → Client profile
/app/[teamSlug]/clients/[clientSlug]/projects  → Client projects
/app/[teamSlug]/clients/[clientSlug]/files     → Client files
/app/[teamSlug]/clients/[clientSlug]/calls     → Call recordings & transcripts
/app/[teamSlug]/clients/[clientSlug]/social    → Social media management
/app/[teamSlug]/clients/[clientSlug]/onboarding → Onboarding checklist

/app/[teamSlug]/projects                       → All projects (cross-client)
/app/[teamSlug]/projects/[projectId]           → Project detail
/app/[teamSlug]/projects/[projectId]/[videoId] → Video review (lawn-style)

/app/[teamSlug]/ai                             → AI chat hub
/app/[teamSlug]/ai/[conversationId]            → AI conversation
/app/[teamSlug]/ai/images                      → AI image generation

/app/[teamSlug]/tools                          → MCP tool browser
/app/[teamSlug]/tools/[serverId]               → MCP server tools

/app/[teamSlug]/workflows                      → Workflow templates
/app/[teamSlug]/workflows/[templateId]         → Workflow builder/editor
/app/[teamSlug]/workflows/active               → Running instances

/app/[teamSlug]/settings                       → Team settings
/app/[teamSlug]/settings/members               → Staff management
/app/[teamSlug]/settings/roles                 → RBAC configuration
/app/[teamSlug]/settings/billing               → Billing / Stripe
/app/[teamSlug]/settings/integrations          → MCP servers, social auth
/app/[teamSlug]/settings/audit                 → Audit log
```

### 5.3 Client Portal (`/portal`)

```
/portal                                  → Client selector (if multi-business)
/portal/[clientSlug]                     → Client dashboard home
/portal/[clientSlug]/projects            → Active projects
/portal/[clientSlug]/projects/[projectId]           → Project detail
/portal/[clientSlug]/projects/[projectId]/[videoId] → Video review + comments
/portal/[clientSlug]/files               → Shared files
/portal/[clientSlug]/notifications       → Notification center
/portal/[clientSlug]/settings            → Client team management
```

### 5.4 Public Routes

```
/share/[token]               → Shared video view (lawn pattern)
/invite/[token]              → Team/client invite acceptance
```

---

## 6. Feature Specifications

### 6.1 STAFF SIDE

#### 6.1.1 AI Chat System

An embedded AI chat interface that allows staff to interact with Claude (or other models) in the context of their work. Conversations can be scoped to a specific client — when they are, the AI has access to client context (profile, projects, files, notes, call transcripts).

**Key behaviors:**
- Model selector (Claude Sonnet, Claude Opus, Gemini Flash, etc.)
- System prompt customization per conversation
- Ability to attach files and images to messages
- Tool use via MCP — the AI can call registered MCP tools mid-conversation
- Conversation history persisted in Convex
- Client-scoped conversations pre-load client context into system prompt

#### 6.1.2 Gemini Image Generation

A dedicated image generation interface powered by Google Gemini.

**Key behaviors:**
- Text-to-image generation with prompt input
- Generated images stored to S3 and referenced in Convex
- Images can be attached to clients, projects, or social posts
- Gallery view of all generated images with search/filter
- Prompt history for re-generation

#### 6.1.3 Video Content (inherited from lawn)

The full lawn video pipeline is preserved — upload, Mux processing, HLS playback, timestamped comments, share links, workflow status (review → rework → done). Extended with client visibility controls and project scoping.

#### 6.1.4 MCP Tool Orchestration

A tool browser and execution interface for MCP-compatible services.

**Key behaviors:**
- Register MCP server endpoints with auth configuration
- Browse available tools per server
- Execute tools with parameter input (form-based UI)
- Execution log with full input/output history
- Tools callable from AI chat (tool use protocol)
- Tools callable from workflow steps (automated)

#### 6.1.5 File Management

General-purpose file upload and organization, scoped to teams, clients, and projects.

**Key behaviors:**
- Drag-and-drop upload (S3 presigned URLs, same pattern as lawn)
- File tagging and search
- Client/project scoping
- Client visibility toggle per file
- Preview for images, PDFs; download for all types

#### 6.1.6 Client Profiles & Onboarding

Structured client records with a configurable onboarding checklist system.

**Key behaviors:**
- Client CRUD with status lifecycle (lead → onboarding → active → paused → churned)
- Configurable onboarding checklist templates
- Checklist step completion tracking with timestamps and notes
- Client profile aggregates: projects, files, calls, social accounts
- Tag-based organization

#### 6.1.7 Admin Center & RBAC

A team administration panel with granular role-based access control.

**Key behaviors:**
- Staff member management (invite, remove, change role)
- Custom permission matrices per role per resource
- Audit log viewer with filters (actor, action, date range)
- Billing management (Stripe subscription controls)
- Integration management (MCP servers, social auth)

#### 6.1.8 Social Media Management

Per-client social media account management and post scheduling.

**Key behaviors:**
- Connect social accounts per client (OAuth flows)
- Post composer with media attachment
- Scheduling with calendar view
- Post status tracking (draft → scheduled → published → failed)
- Per-platform preview

#### 6.1.9 Call Transcription & Recordings

Upload call recordings, auto-transcribe, and attach to client profiles.

**Key behaviors:**
- Audio file upload (S3 storage)
- Async transcription via Deepgram or AssemblyAI (Convex action)
- AI-generated call summary and action items
- Searchable transcript viewer
- Attached to client profile timeline

### 6.2 CLIENT SIDE (Portal)

#### 6.2.1 Client Dashboard

A clean overview of the client's active projects, recent deliverables, and notifications.

#### 6.2.2 Project Management

Clients see only projects marked `clientVisible: true`. Each project shows its videos, files, status, and due date. Clients can track progress without seeing internal workflow details.

#### 6.2.3 Video Review & Comments

The lawn video player and comment system, accessible to client portal users. Comments from clients are flagged with `isClientComment: true` so staff can distinguish internal vs. external feedback.

#### 6.2.4 Notifications

A notification feed showing new video uploads, project status changes, comment replies, and file shares relevant to the client.

#### 6.2.5 Client Team Management

Client admins can invite their own team members to the portal and manage their roles.

---

## 7. Design System

### 7.1 Decision Point

Lawn uses a brutalist, typographic, minimal design (warm cream background, sharp borders, forest green accent). Basecamp should establish its own design language. Two options:

**Option A — Inherit lawn's brutalist aesthetic.** Fast to ship, consistent codebase.

**Option B — Implement a dark, professional dashboard aesthetic.** Better suited for a daily-use operational tool. Recommended approach:
- Dark background (`#0A0A0F`) with subtle surface layers
- Clean sans-serif typography (Inter or Geist)
- Accent color: copper/amber (`#C17F59`) or electric blue
- Card-based layout with subtle borders
- Glassmorphic elements for overlays and modals

### 7.2 Component Library

Inherit lawn's Radix UI + Tailwind + CVA pattern. All primitives from `src/components/ui/` carry over (button, card, dialog, dropdown-menu, input, tabs, tooltip, etc.). Extend with additional components as needed for the admin/client management features.

---

## 8. Environment Variables

All lawn env vars carry over, plus:

```bash
# Lawn (inherited)
VITE_CONVEX_URL=
VITE_CONVEX_SITE_URL=
VITE_CLERK_PUBLISHABLE_KEY=
CLERK_SECRET_KEY=
MUX_TOKEN_ID=
MUX_TOKEN_SECRET=
MUX_WEBHOOK_SECRET=
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=
STRIPE_PRICE_BASIC_MONTHLY=
STRIPE_PRICE_PRO_MONTHLY=

# AI
ANTHROPIC_API_KEY=
GEMINI_API_KEY=

# Transcription
DEEPGRAM_API_KEY=

# Social (per platform)
META_APP_ID=
META_APP_SECRET=
GOOGLE_OAUTH_CLIENT_ID=
GOOGLE_OAUTH_CLIENT_SECRET=
```

---

## 9. Deployment

Identical to lawn: **Vercel** for the frontend SPA, **Convex Cloud** for the backend. The `build:vercel` script handles coordinated deploys. Lawn's `package.json` must be updated to replace `bun` with `npm` and `bunx` with `npx` across all scripts (dev, build, typecheck, etc.).

```bash
# Development
npm run dev          # Vite + Convex dev server

# Production deploy
npx convex deploy --cmd 'npm run build' --cmd-url-env-var-name VITE_CONVEX_URL
```

---

## 10. Development Philosophy (from lawn, extended)

1. **Performance above all else.** Optimistic updates, data preloading on hover, no waterfalls. Convex reactive queries make this natural — lean into it.

2. **Good defaults.** Clients should not need to configure anything. Staff should have sensible defaults that can be overridden.

3. **Convenience.** Minimize clicks. AI chat should be accessible from any context. File uploads should be drag-and-drop everywhere. Client switching should be instant.

4. **Security.** Every Convex mutation checks team membership and role. Client portal queries are strictly scoped — a client can never see another client's data. Share links use the lawn opaque token + optional password pattern.

5. **AI-native.** The system assumes AI is a first-class tool, not an afterthought. AI chat, image gen, transcription summaries, and MCP tools are core features, not bolted-on integrations.

---

## 11. Implementation Phases

### Phase 1 — Foundation (Weeks 1–3)
- Fork lawn, restructure routes into `/app` and `/portal` zones
- Extend Convex schema (clients, clientMembers, files, notifications)
- Implement client CRUD + profile pages
- Implement file upload/management (extend lawn's S3 pattern)
- Role-gated routing (staff vs. client)

### Phase 2 — Core Operations (Weeks 4–6)
- AI chat system (Anthropic SDK integration, Convex persistence)
- Gemini image generation
- Client onboarding checklists
- Notification system (Convex reactive + in-app feed)
- Client portal MVP (projects, videos, comments, files)

### Phase 3 — Advanced Features (Weeks 7–10)
- MCP tool registration and execution
- Workflow engine (templates, instances, step execution)
- Call recording upload + transcription pipeline
- Social media account connection + post scheduling
- RBAC configuration UI + audit log

### Phase 4 — Polish & Scale (Weeks 11–12)
- Admin center refinements
- Search across clients, projects, files, transcripts
- Performance optimization (query batching, prefetching)
- Client portal white-labeling (team branding)
- Documentation and onboarding guides

---

## 12. Open Questions

1. **Design direction** — Brutalist (lawn-native) or dark professional dashboard? (See §7.1)
2. **Social media integration approach** — Direct API integration vs. third-party service (Buffer, Ayrshare, GetLate)?
3. **MCP server hosting** — Self-hosted MCP servers or rely on external providers?
4. **Client billing** — Should the client portal include invoice/payment views, or keep billing strictly in Stripe?
5. **Mobile** — Is a mobile-responsive web app sufficient, or is a native app needed later?
6. **Video generation** — Is AI video generation (Sora, Kling, Seedance) in scope for Phase 1, or deferred?

---

*This spec is a living document. Update as decisions are made and scope is refined.*
