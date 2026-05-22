Sales Performance Dashboard Workbook Specification
1. Business Intent
What the Workbook Does
This workbook is a Sales Performance Analytics Dashboard that enables business users to monitor and analyze transactional sales data across multiple dimensions including time, geography (store regions), products, and customers. It provides both high-level KPIs and detailed drill-down capabilities.

Key Analytical Capabilities
Performance Monitoring: Track total revenue, profit, profit margins, and average order value
Trend Analysis: Visualize revenue and profitability trends over time
Revenue Attribution: Understand revenue mix by region and product type
Top Performer Identification: Identify highest-performing products and customers by profit
Store Economics: Analyze store-level performance with revenue vs. margin scatter plots
Transaction Detail: Access raw transactional data with interactive filtering
User Prompts That Would Generate This Type of Workbook
External users would request this workbook with prompts like:

"Create a sales performance dashboard showing revenue, profit, and key metrics"
"Build an analytics page to track sales by region and product type with filtering controls"
"I need a dashboard with KPIs, trend charts, and top performers analysis for our sales data"
"Show me sales performance with regional breakdown, product mix, and customer insights"
"Create a sales analytics dashboard with date and region filters, showing revenue trends and store economics"
2. Overall Layout Design Choices
Page Structure: Sectional Flow Pattern
The dashboard follows a top-to-bottom sectional flow organized by analytical purpose:

Header Section (Rows 1-4): Controls and title in a single row
KPI Section (Rows 5-16): Four key performance indicators side-by-side
Trend Analysis (Rows 17-31): Time-series combo chart showing revenue and margin
Revenue Mix (Rows 32-46): Side-by-side bar chart (regions) and donut chart (product types)
Top Performers (Rows 47-61): Side-by-side tables for top products and customers
Store Economics (Rows 62-79): Scatter plot with supporting table
Transaction Detail (Rows 80-100): Full-width data table for drill-down
Layout System: Grid-Based with Nested Containers
24-column grid provides flexible layout control
Nested container pattern: Outer containers establish horizontal sections; inner containers enable side-by-side layouts within sections
Full-width sections use columns 1-24
Side-by-side layouts use inner containers spanning 12 grid columns each (50/50 split)
Visual Hierarchy Through Section Headers
Text dividers (prefixed with "━━ ") introduce each analytical section
Section headers span full width (24 columns) and occupy 2 rows
Creates clear visual separation between dashboard components
Headers positioned at top of each container, above the visualizations
Control Placement Strategy
All controls grouped in the top header container
Date control (5 columns) + Region control (4 columns) + Product Type control (3 columns)
Aligned to the right side of the header (columns 13-24)
Title element occupies left side (columns 1-12)
3. Intentional Design Approach for Element Styling
Capability 1: Element Styling (Borders, Corner Radius, Background Colors)
Core Styling Philosophy: Minimalist Card Design
The workbook employs a consistent card-based design system where every data element and container is styled as a subtle card with:

Rounded corners for modern, soft aesthetics
Light borders for gentle visual separation without harsh lines
White backgrounds for clean, readable content areas
Consistent padding to create breathing room around content
Specific Styling Rules
Standard Element Styling (Applied to ALL visualizations and tables):

- Border width: 1px
- Border color: #E8DFD3 (warm light beige)
- Border radius: round
- Background color: #FFFFFF (white)
- Padding: yes (enabled)
Special Case: Header Container

- Border width: 3px (heavier than standard)
- Border color: #ce785c (warm terracotta/coral)
- Border radius: round
- Background color: #FFFFFF
- Padding: yes
Design Rationale
Why Rounded Borders on Everything?

Creates a friendly, approachable interface
Softer than sharp corners, reduces visual harshness
Modern design pattern that signals "these are interactive/important components"
Why Light Beige Borders (#E8DFD3)?

Provides just enough contrast for separation without being distracting
Warmer than pure gray, creates an inviting aesthetic
Consistent with a neutral, professional color scheme
Recedes visually so the data content remains the focus
Why Heavier, Colored Border on Header?

The 3px terracotta border (#ce785c) makes the control panel immediately identifiable
Signals "this is where you interact to filter the dashboard"
Creates visual weight and importance for the filtering area
The warm color adds a touch of brand personality while remaining professional
Why White Backgrounds?

Maximizes readability and data clarity
Creates clean canvas for charts and tables
Provides strong contrast with text and data visualizations
Reduces cognitive load by keeping the interface simple
Why Padding on All Elements?

Prevents chart/table content from touching borders
Creates comfortable white space around data
Improves scannability and reduces visual clutter
Makes each element feel like a self-contained card
When to Apply These Styles
Always apply standard styling (1px beige border, round corners, white background, padding) to:

All charts (bar, donut, combo, scatter, KPI)
All tables (level tables, data tables)
Containers that group visualizations
Apply special header styling (3px terracotta border) to:

The top header container that holds dashboard title + controls
Any container that serves as a primary navigation or control panel
Do NOT apply borders to:

Text divider elements (section headers)
Individual controls within containers (they inherit container styling)
4. Additional Relevant Explanations for Converting Code to Skill
Data Architecture Pattern: Single Source with Metrics
Primary source: One level table (tbl-tx) sourced from a data model table containing transactional data
Source metrics: The data model includes pre-defined metrics (Total Revenue, Total Profit, Profit Margin, AOV, etc.)
Downstream elements: All charts and KPIs reference tbl-tx as their source, ensuring consistent filtering
Control strategy: Controls target the base table, automatically filtering all downstream visualizations
Lesson: When building from a prompt, identify the primary dataset first, create a level table from it, then build all visualizations from that table (not directly from the warehouse source).

Container Nesting Logic
The workbook uses a two-level container nesting pattern:

Page (24 columns × 100 rows)
├─ Container (Outer) [24 columns wide, spans full page width]
│  └─ Container (Inner) [12 columns of parent = 50% width]
│     ├─ Section Header Text
│     ├─ Visualization 1 (left side, 12 columns of inner container)
│     └─ Visualization 2 (right side, 12 columns of inner container)
Why this pattern?

Outer containers establish horizontal rows on the page
Inner containers enable side-by-side layouts within those rows
The inner container spans only 12 of the outer container's 24 columns, creating a 50% width layout
This allows flexible side-by-side arrangements without complex grid math
Lesson: For side-by-side layouts, create an outer container at the page level, then nest an inner container that spans half the width (12 columns). Place visualizations inside the inner container.

Section Header Pattern
Every dashboard section uses:

A text element with prefix "━━ " (Unicode box-drawing character + spaces)
Spans full width (24 columns)
Occupies 2 rows of height
Positioned at the top of each container, above visualizations
No border styling applied
Lesson: When building sectional dashboards, create text dividers with decorative prefixes to visually separate content areas.

KPI Layout Strategy
The four KPIs use:

A dedicated container spanning rows 5-16 (12 rows total)
Inner container for the KPIs themselves (rows 3-12, 10 rows)
Section header at rows 1-2
Each KPI spans 6 columns (24 ÷ 4 = 6 columns per KPI)
Note: Section header is OUTSIDE the KPI container, placed before it
Lesson: For multi-KPI layouts, calculate equal column distribution (24 columns ÷ N KPIs), place all KPIs in a single container row.

Control Configuration
Date control: DateRange variable, targets col-date on base table
Region control: List control sourced from col-store-region, filters same column
Product Type control: List control sourced from col-product-type, filters same column
All controls have bidirectional relationships: they source their options from the table AND filter that table.

Lesson: For dashboard controls, use list controls that pull values from the data element they filter. This ensures the control options match actual data values.

Chart Type Selection Logic
The workbook demonstrates appropriate chart type choices:

Horizontal bar chart: For comparing categorical values (regions) with a single metric
Donut chart: For showing part-to-whole relationships (product type revenue mix)
Combo chart: For dual-axis time series (revenue + margin trend)
Scatter plot: For correlation analysis (revenue vs. margin by store)
KPI: For single summary metrics with prominence
Level table: For detailed ranked lists (top products, top customers) and raw data (transactions)
Lesson: Match visualization type to analytical intent—comparisons use bars, compositions use donuts, relationships use scatter, trends use line/combo.

Aggregation and Sorting Patterns
Charts: All charts use aggregated data with grouping by dimension (region, product type, week)
KPI: Summary mode displaying single aggregate value
Top N tables: Sorted descending by the measure of interest (profit), with ranking implied
Detail table: No aggregation, shows row-level transactions
Lesson: Apply aggregation at the visualization level. Charts should group by dimension and calculate metrics; tables can show either aggregated summaries or raw details.

Color Encoding Example
The "Revenue by Store Region" bar chart uses:

Axis: Region (categorical grouping)
Value: Revenue (primary metric)
Color scale: Colored by AOV (Average Order Value), creating a heat-map effect
Lesson: Color encoding can add a third dimension to 2D charts, encoding additional metrics as color intensity.

Theme Consistency
Highlight color: #0059eb (blue, used for primary interactive elements)
Surface color: #757575 (neutral gray)
Border color: #E8DFD3 (not a theme token, but consistently applied)
Fonts: Source Sans Pro (text), Roboto (data), 400 weight titles
Lesson: Maintain consistent border colors and corner styles across all elements for a cohesive design. Theme colors are used for interactive elements, but border aesthetics are defined at the element level.

Summary for Skill Training
When an external user requests a sales dashboard or performance analytics workbook, the skill should:

Identify the primary dataset and create a base level table from it
Add filtering controls in a top header container with distinctive styling (heavier border)
Structure the page into sections using text dividers and nested containers
Place KPIs prominently near the top in a horizontal row
Use appropriate chart types for each analytical purpose (bar for comparisons, donut for composition, combo for trends, scatter for correlation)
Apply consistent card-style styling to all elements:
1px light beige borders (#E8DFD3)
Rounded corners
White backgrounds
Padding enabled
Use nested containers for side-by-side layouts (outer container at page level, inner container at 50% width)
Create visual hierarchy with section headers using decorative prefixes
Configure controls bidirectionally so they source options from and filter the data they represent
Ensure all visualizations source from the base table to maintain consistent filtering behavior
This pattern creates a professional, clean, and highly functional analytics dashboard that balances aesthetic appeal with analytical power.