Sales Performance Management Workbook - Training Specification
1. Business Intent
What This Workbook Does
This is a Sales Performance Management Dashboard designed for sales operations leaders, regional managers, and sales representatives to monitor, analyze, and forecast sales performance across multiple dimensions (channel, region, branch, rep).

The workbook delivers three interconnected analytical workflows:

Overview Page: Real-time sales performance monitoring with KPIs, funnel analysis, and territory leaderboards
Performance Detail Page: Deep-dive analysis into opportunity aging, loss reasons, and deal-level diagnostics
Forecast & Retro Page: Forward-looking pipeline coverage, forecast submissions, and retrospective notes with collaborative elements (form + input table)
Typical User Prompts That Would Generate This Type of Workbook
Executive-level requests:

"Create a sales performance dashboard showing bookings, win rates, and pipeline coverage by region and rep"
"Build an executive sales dashboard with KPIs, funnel charts, and a territory leaderboard"
"I need a sales analytics workbook to track monthly performance across channels, regions, and reps"
Operational analysis requests:

"Show me where deals are getting stuck in our pipeline with aging analysis by stage"
"Create a dashboard to analyze win/loss reasons and identify bottlenecks in our sales process"
"Build a performance detail view showing deal-level data with drill-down capabilities"
Planning & forecasting requests:

"Create a forecast submission tool where reps can enter commit, best case, and upside numbers"
"Build a pipeline coverage dashboard that shows forecast vs plan with collaborative notes"
"I need a forecast and retrospective page where teams can submit predictions and track actuals"
Key indicators of this pattern:

Multi-dimensional filtering (time, geography, org hierarchy, channel)
Mix of aggregated KPIs + detailed visualizations + transactional tables
Collaborative/input elements (forms, input tables) alongside analytical elements
Territory/rep performance comparison and leaderboarding
Pipeline funnel and stage progression analysis
2. Overall Layout Design Choices
Page Structure Pattern
All three main operational pages follow a consistent vertical flow architecture:

┌─────────────────────────────────────┐
│  Container 1: Control Bar (filters) │  ← Fixed height, full width
├─────────────────────────────────────┤
│  Container 2: KPI Banner (metrics)   │  ← Fixed height, nested sub-containers
├─────────────────────────────────────┤
│  Container 3: Content Area (viz/tbl) │  ← Flexible height, nested layouts
└─────────────────────────────────────┘
Grid System
24-column grid across all pages for precise, responsive layouts
Pages use sub-grid architecture: top-level containers subdivide into their own 24-column grids
This allows independent sizing within each section while maintaining global alignment
Container Nesting Strategy
Three-tier hierarchy:

Tier 1 (Page-level containers): Logical sections (controls, KPIs, content)
Tier 2 (Sub-containers): Group related elements (e.g., "Container 2.1" groups 4 KPIs)
Tier 3 (Elements): Individual visualizations, controls, tables
Why this matters:

Containers have no gap between elements (ContainerSpacing = 0), relying on borders and padding for visual separation
Nested containers enable grouped styling — apply background/border to parent, inherit or override on children
The pattern creates visual bands without sacrificing grid precision
KPI Layout Pattern
KPIs are arranged in horizontal rows of 4, each occupying 6 columns (6w × 5h):

Container 2.1: Primary KPIs (Bookings ACV, MRR Added, New Customers, Win Rate)
Container 2.2: Secondary KPIs (Avg Deal Size, Lead → Won %, Activation Rate, Pipeline Coverage)
This two-row KPI banner creates a scannable metrics section while maintaining equal visual weight.

Content Area Flexibility
Container 3 accommodates diverse layouts:

Overview: 2 charts side-by-side, then 2 full-width tables below
Performance Detail: 2 charts side-by-side, then 1 full-width detail table
Forecast & Retro: Pivot table + chat + input table + form in a flexible arrangement
Hidden Data Sources Page
A dedicated "Data sources" page houses all staging tables, separating data transformation from presentation — a best practice for maintainability.

3. Element Styling — Design Approach for Capability 1
Color Palette System
Background Colors
Light blue (#e5f5ff): Primary container background — establishes branded surface for all control bars and KPI sections
Medium blue (#74A1C8): Accent container background — used on the top KPI row (Container 2.1) to create hierarchy
White (#FFFFFF): Forms and data-entry elements — signals interactivity and input areas
None/Transparent: Content containers (Container 3) — lets charts and tables breathe
Border Colors
Steel blue (#4E79A7): Strong borders on control bars (Container 1) — frames the filtering interface
Light gray (#f7f7f7): Subtle borders on KPI containers — delineates sections without competing with content
Medium gray (#e0e0e0): Form borders — clean, neutral framing for input areas
Border Width Strategy
Consistent 3px borders across all containers — creates a bold, structured aesthetic
Thicker borders signal intentional zones rather than delicate dividers
This approach works because borders use low-contrast colors (light blue backgrounds + light gray borders)
Corner Radius (Border Radius)
Round corners (border_radius: round) on:
All containers on Performance Detail and Forecast pages
Forms and input elements
Sharp corners (no radius) on:
Overview page containers (Container 1, 2, 3)
Rationale: The Overview page uses a more traditional "banded" dashboard layout with full-width sections, so sharp corners maintain alignment and structure. Detail pages use rounded corners to soften the interface and create discrete "cards" for each functional area.

Padding Strategy
Padding enabled on:
Performance Detail and Forecast containers
Forms
No padding on:
Overview page containers
This aligns with the corner radius approach: card-like containers get padding for breathing room; full-bleed bands get none.

Design Principles Demonstrated
1. Visual Hierarchy Through Color Layering
Control Bar (dark border #4E79A7) 
  ↓ More important
KPI Row 1 (medium bg #74A1C8, dark border)
  ↓
KPI Row 2 (light bg #e5f5ff, light border #f7f7f7)
  ↓
Content Area (no bg, light border)
  ↓ Less structural weight
2. Consistency With Purpose
Every control bar across all 3 pages: same bg (#e5f5ff) + same border (#4E79A7, 3px)
Immediate visual recognition: "This is where I filter"
3. Contrast Through Differentiation
Input elements (forms, input tables) use white backgrounds to stand out from analytical containers (#e5f5ff)
Signals: "You can interact with this"
4. Conditional Formfitting and Data Visualization Stylingatting
Level tables use conditional formatting extensively:
Color scales on performance metrics (Win Rate, Avg Deal) with sequential teals or default gradients
Data bars on booking columns — immediate visual comparison
Background coloring for heatmap-style insights
Example Pattern Application
To create a similar workbook:

Set up container structure:

Container 1: bg_color="#e5f5ff", border_color="#4E79A7", border_width="3px", border_radius="round" (if detail page), padding=True/False
Container 2: bg_color="#e5f5ff", border_color="#f7f7f7", border_width="3px"
Sub-container 2.1: bg_color="#74A1C8", border_color="#4E79A7" (accent row)
Sub-container 2.2: bg_color="#e5f5ff", border_color="#f7f7f7" (secondary row)
Container 3: bg_color=None, border_color="#f7f7f7", border_width="3px"
Apply KPI layout:

4 KPIs per row, each 6 columns wide × 5 rows tall
Place inside nested sub-containers to group and style together
Style input elements differently:

Forms: bg_color="#FFFFFF", border_color="#e0e0e0", border_radius="round", padding=True
Use conditional formatting strategically:

Color scales on percentage/rate columns (background target)
Data bars on absolute value columns (Bookings, Revenue)
This creates a professional, data-dense, brand-cohesive sales analytics experience suitable for executive audiences.

Training Note: This workbook demonstrates advanced Sigma capabilities including nested containers with custom styling, multi-level grouping tables, conditional formatting, form-based data collection, and coordinated filtering across pages. It's an excellent reference for building operational BI applications that blend analysis, reporting, and collaboration in a single interface.