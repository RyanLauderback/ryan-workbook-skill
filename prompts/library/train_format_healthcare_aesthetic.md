Workbook Training Specification: Healthcare Department Performance Dashboard

1. Business Intent

What This Workbook Does
This workbook provides a comprehensive healthcare operations dashboard that monitors department performance across multiple dimensions: patient care quality, predictive analytics, operational efficiency, and financial performance. It's designed for healthcare executives and department managers who need to track key operational metrics, identify trends, and make data-driven decisions about resource allocation and patient care.

User Prompts That Would Generate This Type of Workbook
Users seeking to build similar workbooks might ask:

"Create an executive dashboard for hospital operations showing patient satisfaction, infection rates, bed occupancy, wait times, and financial metrics by department"
"Build a healthcare analytics workbook with KPIs for readmission rates, operational capacity, and predictive staffing needs"
"Design a multi-section dashboard tracking patient care quality, operational efficiency, and revenue performance with time-series visualizations"
"Create a hospital management dashboard with geographic occupancy rates, department comparisons, and predictive admission forecasting"
"Build an operations dashboard showing current metrics compared to last month with drill-down capabilities by department and location"

Key Characteristics
Multi-dimensional analysis: Combines clinical (infection rates, patient satisfaction), operational (wait times, occupancy), and financial (cost per patient, revenue) metrics
Temporal intelligence: Includes both historical trend analysis and forward-looking predictive insights
Geographic awareness: Incorporates location-based analysis with regional map visualizations
Comparative context: KPIs show period-over-period comparisons (vs. last month)
Hierarchical filtering: Centralized filter controls for Date and Department that cascade across all visualizations

2. Overall Layout Design Choices

Page Architecture
The workbook uses a three-page structure with distinct purposes:
- (main page): Comprehensive dashboard with all analytics
- Modal/overlay page for detailed geographic drill-down
- Modal/overlay page for centralized filter controls

Grid System
Main page grid: 24 columns × 70 rows (wide, scrollable canvas)
Modal pages: 12 columns × 12 rows (compact, focused)
Container sub-grids: 12 columns (standardized internal layout)

Vertical Organization Pattern
The main dashboard follows a top-to-bottom narrative flow:
Header section (rows 1-3): Title with flanking logo images
KPI summary bar (rows 4-12): Four key metrics in a horizontal container with filter access
Three-column analytical section (rows 13-40): Patient Care Quality | Operational Efficiency | Financial Performance
Full-width predictive section (rows 41-58): Future admissions and staffing projections

Horizontal Layout Strategy
Equal-width columns: The three analytical containers (rows 13-40) each occupy 8 of 24 columns (33% width)
Symmetrical spacing: Creates visual balance and allows side-by-side comparison
Full-width emphasis: Predictive insights span all 24 columns to signal importance and accommodate larger data tables

Container Hierarchy
Each thematic section is wrapped in a named container that:
Groups related visualizations logically
Provides consistent styling boundaries
Enables coordinated padding and spacing
Facilitates maintenance (e.g., "Cont - PCQ" for Patient Care Quality)

Content Density Approach
Compact KPIs: 7 rows tall, 3 columns wide each (efficient use of prime real estate)
Standard chart height: 12 rows for most bar/line/donut charts
Breathing room: Dividers (1 row) and descriptive text (1 row) separate sections
Icon accents: Small image elements (1 column × 2 rows) add visual interest without consuming space

3. Element Styling Design Approach (Capability 1)

Design Philosophy
The styling strategy creates visual hierarchy through selective emphasis rather than uniform decoration. Not all containers receive the same treatment—styling choices signal importance and group related content.

Border Strategy
Subtle Borders for Grouping
Color: #686868 (medium gray) for most containers
Width: 1px (thin, non-intrusive)
Purpose: Defines boundaries without overwhelming the content

Accent Borders for Hierarchy
Header container: Uses #7586a2 (blue-gray) to distinguish the title area
KPI container: Standard gray border, no background color (keeps focus on metrics)

When Borders Are Applied
All major containers receive borders to establish clear content zones
Top-level groupings (KPI bar, analytical sections, predictive section)
Individual visualizations within containers do NOT have additional borders (avoids visual clutter)

Background Color Strategy

White Backgrounds for Content Sections
Color: #FFFFFF (pure white)
Applied to: All four analytical containers
  - (Patient Care Quality)
  - (Predictive Insights)
  - (Operational Efficiency)
  - (Financial Performance)

Transparent/Default Backgrounds for Emphasis
KPI container: No explicit background color
Header container: No explicit background color
Purpose: Allows these sections to blend with the page background, making white-background sections "pop" forward

Design Rationale
The selective use of white backgrounds creates visual cards that:
Group related analytics into digestible chunks
Provide contrast against the page background
Signal "this is a complete analytical unit"
Reduce cognitive load by clearly separating concerns

Border Radius (Corner Rounding)
Rounded Corners for Modern Aesthetic
Value: round (Sigma's predefined rounded setting)
Applied to: All four white-background analytical containers
NOT applied to: KPI bar and header (sharp corners maintain formality)

Design Intent
Softens the interface: Rounded corners feel approachable and modern
Reinforces card metaphor: Combined with white backgrounds, creates distinct "card" UI pattern
Selective application: Only containers with backgrounds get rounded corners (rounding a transparent container would be invisible)

Padding Strategy
Consistent Internal Spacing
All containers have padding enabled
Purpose: Prevents content from touching container edges
Effect: Creates comfortable whitespace around visualizations, text, and charts

No Gap Between Elements
All containers specify "No gap between elements"
Rationale: Padding provides the spacing; additional gaps would create excessive whitespace
Benefit: Maximizes data density while maintaining readability

Button Styling Example
The (filter access) button demonstrates accent styling for interactive elements:
Shape: pill (fully rounded ends)
Fill color: #BEDBEE (soft blue)
Font color: var(--colors-textNeutralSoft) (theme-aware neutral text)
Size: medium
Alignment: right (positioned at the end of the KPI bar)
This styling makes the filter access point visually distinct from data elements while maintaining a friendly, approachable appearance.

Image Element Integration
Small icon images (1 column × 2 rows) are positioned at the top-left of each analytical container:
Fit: contain (preserves aspect ratio)
Shape: rectangle
Purpose: Provides visual branding/categorization without text labels
Placement: Overlaps with section title text, creating a cohesive header

Styling Pattern Summary
Element Type           Border  Border Color  Background  Border Radius  Padding
Header container       1px     #7586a2       None        No             Yes
KPI container          1px     #686868       None        No             Yes
Analytical containers  1px     #686868       #FFFFFF     Round          Yes
Nested containers      Inherits Inherits    Inherits    Inherits       Yes
Individual viz elements None  N/A           None        N/A            N/A

Key Takeaways for Training
Hierarchy through contrast: Use background colors selectively to create visual hierarchy, not uniformly
Border consistency: Maintain consistent border width (1px) but vary color for emphasis
Rounded corners = cards: Apply border radius only to containers with backgrounds to reinforce the card UI pattern
Padding everywhere: Always enable padding on containers to prevent edge-touching content
Minimal decoration on data: Let visualizations speak for themselves—don't add borders to individual charts
Accent colors sparingly: Use distinct border colors (like #7586a2) only for top-level hierarchy elements

This specification provides the foundational understanding needed to train an external workbook-building skill on how to replicate this dashboard's professional, hierarchical, and user-friendly design approach.
