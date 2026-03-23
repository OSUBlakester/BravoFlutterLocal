// --- Global Flags ---
let isAuthContextReady = false;
let isDomContentLoaded = false;

let startDateInput = null; 
let endDateInput = null; 
let fetchReportButton = null; 
let reportTableBody = null;
let reportStatus = null;
let toggleRawDataButton = null;
let rawDataTableContainer = null;

// Elements for Global Page Activity Report
let fetchGlobalActivityReportButton = null;
let globalActivityReportStatus = null;
let globalPageActivityChartCanvas = null;
let globalPageActivityList = null;
let toggleGlobalChartTypeButton = null;
let globalPageActivityChartInstance = null; // To hold the chart instance
let currentGlobalChartType = 'bar'; // Default chart type
let lastGlobalReportData = []; // Store the data for re-rendering chart

// Elements for Page Scope Button Activity Report
let pageSelectorDropdown = null;
let fetchPageButtonReportButton = null;
let pageButtonReportStatus = null;
let pageButtonActivityChartCanvas = null;
let pageButtonActivityList = null;
let pageButtonActivityChartInstance = null;
  
// Set default date range (e.g., last 24 hours)
const now = new Date();
const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000);

// --- Initialization Function ---
async function initializePage() {
    if (isAuthContextReady && isDomContentLoaded) {
        console.log("user_diary_admin.js: Auth context and DOM ready. Initializing page.");

        // Assign DOM Elements
        startDateInput = document.getElementById('startDate');
        endDateInput = document.getElementById('endDate');
        fetchReportButton = document.getElementById('fetchReportButton');
        reportTableBody = document.getElementById('reportTableBody');
        reportStatus = document.getElementById('reportStatus');
        toggleRawDataButton = document.getElementById('toggleRawDataButton');
        rawDataTableContainer = document.getElementById('rawDataTableContainer');

        // Elements for Global Page Activity Report
        fetchGlobalActivityReportButton = document.getElementById('fetchGlobalActivityReportButton');
        globalActivityReportStatus = document.getElementById('globalActivityReportStatus');
        globalPageActivityChartCanvas = document.getElementById('globalPageActivityChart');
        globalPageActivityList = document.getElementById('globalPageActivityList');
        toggleGlobalChartTypeButton = document.getElementById('toggleGlobalChartTypeButton');

        // Elements for Page Scope Button Activity Report
        pageSelectorDropdown = document.getElementById('pageSelectorDropdown');
        fetchPageButtonReportButton = document.getElementById('fetchPageButtonReportButton');
        pageButtonReportStatus = document.getElementById('pageButtonReportStatus');
        pageButtonActivityChartCanvas = document.getElementById('pageButtonActivityChart');
        pageButtonActivityList = document.getElementById('pageButtonActivityList');

        // Format for datetime-local input: YYYY-MM-DDTHH:mm
        endDateInput.value = now.toISOString().slice(0, 16);
        startDateInput.value = yesterday.toISOString().slice(0, 16);

        // Basic check for essential elements
        //if (!startDateInput || !endDateInput || !fetchReportButton || !reportTableBody || !reportStatus || !toggleRawDataButton || !rawDataTableContainer  || fetchGlobalActivityReportButton || !globalActivityReportStatus || !globalPageActivityChartCanvas || !globalPageActivityList || !toggleGlobalChartTypeButton || !pageSelectorDropdown || !fetchPageButtonReportButton || !pageButtonReportStatus || !pageButtonActivityChartCanvas || !pageButtonActivityList) {
        //    console.error("CRITICAL ERROR: One or more essential DOM elements for admin_audit_report.js not found.");
        //    return;
        //}

        // Add Event Listeners
        fetchReportButton.addEventListener('click', fetchAuditReport);

        toggleRawDataButton.addEventListener('click', () => {
            const isHidden = rawDataTableContainer.classList.toggle('hidden');
            toggleRawDataButton.textContent = isHidden ? 'Show Raw Data Table' : 'Hide Raw Data Table';
        });


        // Initialize sorting state
        let sortColumn = null;
        let sortDirection = 'asc';
        let currentReportData = []; // To store fetched data for sorting

        if (fetchGlobalActivityReportButton) {
            fetchGlobalActivityReportButton.addEventListener('click', fetchAndRenderGlobalPageActivity);

        }

        if (toggleGlobalChartTypeButton) {
            toggleGlobalChartTypeButton.addEventListener('click', () => {
                if (currentGlobalChartType === 'bar') {
                    currentGlobalChartType = 'pie';
                    toggleGlobalChartTypeButton.textContent = 'Show Bar Chart';
                } else {
                    currentGlobalChartType = 'bar';
                    toggleGlobalChartTypeButton.textContent = 'Show Pie Chart';
                }
                // Re-render the chart with the new type if data is available
                if (lastGlobalReportData.length > 0) {
                    renderGlobalPageActivityChart(lastGlobalReportData, currentGlobalChartType);
                }
            });
        }

        if (fetchPageButtonReportButton) {
            fetchPageButtonReportButton.addEventListener('click', fetchAndRenderPageButtonActivity);
        }


    // Initial Data Load
    populatePageSelector(); // Populate dropdown on load

}
}


function showStatus(message, isError = false, duration = 5000) {
    reportStatus.textContent = message;
    reportStatus.className = `mb-4 text-sm ${isError ? 'text-red-600' : 'text-green-600'}`;
    if (duration > 0) {
        setTimeout(() => {
            if (reportStatus.textContent === message) {
                reportStatus.textContent = '';
                reportStatus.className = 'mb-4 text-sm';
            }
        }, duration);
    }
}

async function fetchAuditReport() {
    const startDate = startDateInput.value;
    const endDate = endDateInput.value;

    if (!startDate || !endDate) {
        showStatus("Please select both a start and end date.", true);
        return;
    }

    // Convert local datetime-local input to ISO string with Z for UTC
    // The backend expects ISO format.
    const startISO = new Date(startDate).toISOString();
    const endISO = new Date(endDate).toISOString();

    if (new Date(startISO) >= new Date(endISO)) {
        showStatus("Start date must be before end date.", true);
        return;
    }

    showStatus("Fetching report...", false, 0);
    reportTableBody.innerHTML = '<tr><td colspan="7" class="table-cell text-center">Loading...</td></tr>';

    try {
        const response = await window.authenticatedFetch(`/api/audit/activity-report?start_date=${encodeURIComponent(startISO)}&end_date=${encodeURIComponent(endISO)}`,
        { // ** NEW Endpoint **
        headers: { 'Content-Type': 'application/json' }, 
    }
    );

        if (!response.ok) {
            const errorData = await response.json().catch(() => ({ detail: `HTTP error ${response.status}` }));
            throw new Error(errorData.detail || `Failed to fetch report: ${response.statusText}`);
        }

        const reportData = await response.json();
        currentReportData = reportData; // Store for sorting
        renderReport(reportData);
        showStatus(`Report loaded. Found ${reportData.length} entries.`, false);

    } catch (error) {
        console.error('Error fetching audit report:', error);
        showStatus(`Error: ${error.message}`, true);
        reportTableBody.innerHTML = `<tr><td colspan="7" class="table-cell text-center text-red-500">Error loading report: ${error.message}</td></tr>`;
    }
}

function renderReport(data, columnToSort = null, direction = 'asc') {
    reportTableBody.innerHTML = ''; // Clear previous results

    if (!Array.isArray(data) || data.length === 0) {
        reportTableBody.innerHTML = '<tr><td colspan="7" class="table-cell text-center">No data found for the selected period.</td></tr>';
        return;
    }

    // Sort data
    if (columnToSort) {
        data.sort((a, b) => {
            let valA = a[columnToSort];
            let valB = b[columnToSort];

            // Handle different data types for sorting
            if (columnToSort === 'timestamp') {
                valA = new Date(valA);
                valB = new Date(valB);
            } else if (typeof valA === 'string') {
                valA = valA.toLowerCase();
                valB = valB.toLowerCase();
            } else if (typeof valA === 'boolean') {
                valA = valA ? 1 : 0;
                valB = valB ? 1 : 0;
            }

            if (valA < valB) return direction === 'asc' ? -1 : 1;
            if (valA > valB) return direction === 'asc' ? 1 : -1;
            return 0;
        });
    } else { // Default sort by timestamp descending
        data.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
    }

    data.forEach(entry => {
        const row = reportTableBody.insertRow();

        const timestampCell = row.insertCell();
        timestampCell.className = 'table-cell';
        timestampCell.textContent = new Date(entry.timestamp).toLocaleString();

        const pageNameCell = row.insertCell();
        pageNameCell.className = 'table-cell';
        pageNameCell.textContent = entry.page_name || 'N/A';

        ['button_text', 'button_summary'].forEach(key => {
            const cell = row.insertCell();
            cell.className = 'table-cell';
            cell.textContent = entry[key] || '';
        });

        row.insertCell().textContent = entry.is_llm_generated ? 'Yes' : 'No';
        row.insertCell().textContent = entry.originating_button_text || '';
        row.insertCell().textContent = entry.page_context_prompt || '';
        
        Array.from(row.cells).forEach(cell => cell.classList.add('table-cell'));
    });

}

// Add sort listeners to table headers
document.querySelectorAll('#rawDataTableContainer th').forEach((headerCell, index) => {
    headerCell.addEventListener('click', () => {
        const columnKey = getColumnKeyByIndex(index);
        if (!columnKey) return;

        if (sortColumn === columnKey) {
            sortDirection = sortDirection === 'asc' ? 'desc' : 'asc';
        } else {
            sortColumn = columnKey;
            sortDirection = 'asc';
        }
        renderReport(currentReportData, sortColumn, sortDirection);
    });
});

function getColumnKeyByIndex(index) {
    // This needs to match your table structure
    const columnKeys = [
        'timestamp', 'page_name', 'button_text', 'button_summary',
        'is_llm_generated', 'originating_button_text', 'page_context_prompt'
    ];
    return columnKeys[index] || null;
}

// --- Global Page Activity Report Functions ---
async function fetchAndRenderGlobalPageActivity() {
    showGlobalActivityStatus("Fetching global page activity report...", false, 0);
    globalPageActivityList.innerHTML = '<li>Loading...</li>';
    if (globalPageActivityChartInstance) {
        globalPageActivityChartInstance.destroy();
        globalPageActivityChartInstance = null;
    }

    try {
        const response = await window.authenticatedFetch('/api/audit/reports/global-page-activity',
            { // ** NEW Endpoint **
        headers: { 'Content-Type': 'application/json' }, 
    }
        );
        if (!response.ok) {
            const errorData = await response.json().catch(() => ({ detail: `HTTP error ${response.status}` }));
            throw new Error(errorData.detail || `Failed to fetch report: ${response.statusText}`);
        }
        const reportData = await response.json();

        if (!Array.isArray(reportData) || reportData.length === 0) {
            showGlobalActivityStatus("No global page activity data found.", false);
            globalPageActivityList.innerHTML = '<li>No data to display.</li>';
            return;
        }

        lastGlobalReportData = reportData; // Store for potential re-renders
        renderGlobalPageActivityChart(reportData, currentGlobalChartType); // Pass current chart type
        renderGlobalPageActivityList(reportData);
        showGlobalActivityStatus(`Global page activity report loaded. Found ${reportData.length} page entries.`, false);

    } catch (error) {
        console.error('Error fetching global page activity report:', error);
        showGlobalActivityStatus(`Error: ${error.message}`, true);
        globalPageActivityList.innerHTML = `<li class="text-red-500">Error loading report: ${error.message}</li>`;
    }
}

function renderGlobalPageActivityChart(data, chartType = 'bar') {
    if (globalPageActivityChartInstance) {
        globalPageActivityChartInstance.destroy();
    }
    const ctx = globalPageActivityChartCanvas.getContext('2d');

    // Prepare data for chart - top N pages or all if less than N
    const topN = 15;
    const sortedData = [...data].sort((a, b) => b.clicks - a.clicks); // Sort by clicks desc
    // For pie chart, filter out 0-click items as they don't make sense. For bar, they are fine.
    const chartData = chartType === 'pie'
        ? sortedData.slice(0, topN).filter(item => item.clicks > 0)
        : sortedData.slice(0, topN);

    if (chartData.length === 0 && chartType === 'pie') {
        showGlobalActivityStatus("No data with clicks > 0 to display in Pie Chart.", false);
        // Optionally, you could draw an empty state on the canvas or just leave it blank
        return;
    }

    let chartConfig;

    if (chartType === 'pie') {
        const pieColors = chartData.map((_, index) => {
            const hue = (index * (360 / Math.max(1, chartData.length))) % 360; // Distribute hues
            return `hsl(${hue}, 70%, 60%)`;
        });
        chartConfig = {
            type: 'pie',
            data: {
                labels: chartData.map(item => item.page_name),
                datasets: [{
                    label: 'Page Clicks',
                    data: chartData.map(item => item.clicks),
                    backgroundColor: pieColors,
                    hoverOffset: 4
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'top',
                    },
                    title: {
                        display: true,
                        text: `Top ${chartData.length} Visited Pages (Excl. Home)`
                    },
                    tooltip: {
                        callbacks: {
                            label: function(context) {
                                let label = context.label || '';
                                if (label) {
                                    label += ': ';
                                }
                                if (context.parsed !== null) {
                                    label += context.parsed + ' clicks';
                                }
                                return label;
                            }
                        }
                    }
                }
            }
        };
    } else { // 'bar' chart
        chartConfig = {
            type: 'bar',
            data: {
                labels: chartData.map(item => item.page_name),
                datasets: [{
                    label: 'Page Clicks',
                    data: chartData.map(item => item.clicks),
                    backgroundColor: chartData.map(item => item.clicks > 0 ? 'rgba(54, 162, 235, 0.6)' : 'rgba(255, 99, 132, 0.2)'),
                    borderColor: chartData.map(item => item.clicks > 0 ? 'rgba(54, 162, 235, 1)' : 'rgba(255, 99, 132, 1)'),
                    borderWidth: 1
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        beginAtZero: true,
                        ticks: { stepSize: 1 }
                    },
                    x: {
                        ticks: { autoSkip: false, maxRotation: 70, minRotation: 45 
                            
                        }
                    }
                },
                plugins: {
                    legend: { display: false },
                    title: { display: true, text: `Top ${chartData.length} Visited Pages (Excl. Home)` }
                }
            }
        };
    }
    globalPageActivityChartInstance = new Chart(ctx, chartConfig);
}

function renderGlobalPageActivityList(data) {
    globalPageActivityList.innerHTML = ''; // Clear previous list
    if (data.length === 0) {
        globalPageActivityList.innerHTML = '<li>No page activity data to display.</li>';
        return;
    }
    data.forEach(item => {
        const listItem = document.createElement('li');
        listItem.textContent = `${item.page_name}: ${item.clicks} clicks ${item.is_defined ? '' : '(Not currently defined in pages.json)'}`;
        if (item.clicks === 0 && item.is_defined) {
            listItem.classList.add('text-orange-600', 'font-semibold'); // Highlight unused defined pages
        } else if (!item.is_defined && item.clicks > 0) {
            listItem.classList.add('text-red-600', 'italic'); // Highlight clicked but undefined pages
        }
        globalPageActivityList.appendChild(listItem);
    });
}

function showGlobalActivityStatus(message, isError = false, duration = 5000) {
    globalActivityReportStatus.textContent = message;
    globalActivityReportStatus.className = `mb-4 text-sm ${isError ? 'text-red-600' : 'text-green-600'}`;
    if (duration > 0) {
        setTimeout(() => {
            if (globalActivityReportStatus.textContent === message) {
                globalActivityReportStatus.textContent = '';
                globalActivityReportStatus.className = 'mb-4 text-sm';
            }
        }, duration);
    }
}

// --- Page Scope Button Activity Report Functions ---
async function populatePageSelector() {
    if (!pageSelectorDropdown) return;
    try {
        const response = await window.authenticatedFetch('/api/page-names',
            {
                headers: { 'Content-Type': 'application/json' }, 
            }
        );
        if (!response.ok) throw new Error('Failed to load page names');
        const pageNames = await response.json();
        pageSelectorDropdown.innerHTML = '<option value="">-- Select a Page --</option>'; // Clear loading/default
        if (pageNames.length === 0) {
            pageSelectorDropdown.innerHTML = '<option value="">No pages found</option>';
            return;
        }
        pageNames.forEach(name => {
            const option = document.createElement('option');
            option.value = name;
            option.textContent = name;
            pageSelectorDropdown.appendChild(option);
        });
    } catch (error) {
        console.error("Error populating page selector:", error);
        pageSelectorDropdown.innerHTML = '<option value="">Error loading pages</option>';
        showPageButtonStatus(`Error loading page list: ${error.message}`, true);
    }
}

async function fetchAndRenderPageButtonActivity() {
    const selectedPageName = pageSelectorDropdown.value;
    if (!selectedPageName) {
        showPageButtonStatus("Please select a page.", true);
        return;
    }

    showPageButtonStatus(`Fetching button activity for page: ${selectedPageName}...`, false, 0);
    pageButtonActivityList.innerHTML = '<li>Loading...</li>';
    if (pageButtonActivityChartInstance) {
        pageButtonActivityChartInstance.destroy();
        pageButtonActivityChartInstance = null;
    }

    try {
        const response = await window.authenticatedFetch(`/api/audit/reports/page-button-activity/${encodeURIComponent(selectedPageName)}`,
        { // ** NEW Endpoint **
                headers: { 'Content-Type': 'application/json' }, 
        }
    );
        if (!response.ok) {
            const errorData = await response.json().catch(() => ({ detail: `HTTP error ${response.status}` }));
            throw new Error(errorData.detail || `Failed to fetch report for ${selectedPageName}: ${response.statusText}`);
        }
        const reportData = await response.json();

        if (!Array.isArray(reportData) || reportData.length === 0) {
            showPageButtonStatus(`No button activity data found for page: ${selectedPageName}.`, false);
            pageButtonActivityList.innerHTML = '<li>No data to display.</li>';
            return;
        }

        renderPageButtonActivityChart(reportData, selectedPageName);
        renderPageButtonActivityList(reportData);
        showPageButtonStatus(`Report loaded for page: ${selectedPageName}. Found ${reportData.length} button entries.`, false);

    } catch (error) {
        console.error(`Error fetching report for page ${selectedPageName}:`, error);
        showPageButtonStatus(`Error: ${error.message}`, true);
        pageButtonActivityList.innerHTML = `<li class="text-red-500">Error loading report: ${error.message}</li>`;
    }
}

function renderPageButtonActivityChart(data, pageName) {
    if (pageButtonActivityChartInstance) {
        pageButtonActivityChartInstance.destroy();
    }
    const ctx = pageButtonActivityChartCanvas.getContext('2d');
    const topN = 15;
    const sortedData = [...data].sort((a, b) => b.clicks - a.clicks);
    const chartData = sortedData.slice(0, topN).filter(item => item.clicks > 0); // Only show buttons with clicks

    if (chartData.length === 0) {
        showPageButtonStatus("No buttons with clicks > 0 to display in chart for this page.", false, 0);
        // Optionally clear canvas or draw "No data"
        return;
    }

    pageButtonActivityChartInstance = new Chart(ctx, {
        type: 'bar', // Default to bar, can add toggle later
        data: {
            labels: chartData.map(item => item.button_text.length > 20 ? item.button_text.substring(0,17) + '...' : item.button_text),
            datasets: [{
                label: 'Button Clicks',
                data: chartData.map(item => item.clicks),
                backgroundColor: chartData.map(item => {
                    if (item.source_type === "Defined Static") return 'rgba(54, 162, 235, 0.7)'; // Blue for static
                    if (item.source_type === "LLM Generated Click") return 'rgba(75, 192, 192, 0.7)'; // Teal for LLM
                    return 'rgba(255, 159, 64, 0.7)'; // Orange for other
                }),
                borderColor: chartData.map(item => {
                    if (item.source_type === "Defined Static") return 'rgba(54, 162, 235, 1)';
                    if (item.source_type === "LLM Generated Click") return 'rgba(75, 192, 192, 1)';
                    return 'rgba(255, 159, 64, 1)';
                }),
                borderWidth: 1
            }]
        },
        options: {
            responsive: true, maintainAspectRatio: false,
            scales: { y: { beginAtZero: true, ticks: { stepSize: 1 } }, x: { ticks: { autoSkip: false, maxRotation: 70, minRotation: 45 }}},
            plugins: { legend: { display: true, position: 'top', labels: { generateLabels: function(chart) { /* Custom legend if needed */ return Chart.defaults.plugins.legend.labels.generateLabels(chart); } } }, title: { display: true, text: `Top Button Clicks for Page: ${pageName}` } }
        }
    });
}

function renderPageButtonActivityList(data) {
    pageButtonActivityList.innerHTML = '';
    if (data.length === 0) {
        pageButtonActivityList.innerHTML = '<li>No button activity data to display for this page.</li>';
        return;
    }
    data.forEach(item => {
        const listItem = document.createElement('li');
        let typeLabel = item.source_type;
        if (item.source_type === "Defined Static" && item.clicks === 0) {
            listItem.classList.add('text-orange-600', 'font-semibold'); // Highlight unused defined
            typeLabel += " (Unused)";
        } else if (item.source_type === "Clicked (Not Defined Static)") {
            listItem.classList.add('text-purple-600', 'italic');
        }
        listItem.textContent = `${item.button_text}: ${item.clicks} clicks (Type: ${typeLabel})${item.button_summary && item.button_summary !== item.button_text ? ' - Summary: ' + item.button_summary : ''}`;
        pageButtonActivityList.appendChild(listItem);
    });
}

function showPageButtonStatus(message, isError = false, duration = 5000) {
    pageButtonReportStatus.textContent = message;
    pageButtonReportStatus.className = `mb-4 text-sm ${isError ? 'text-red-600' : 'text-green-600'}`;
    if (duration > 0) { setTimeout(() => { if (pageButtonReportStatus.textContent === message) { pageButtonReportStatus.textContent = ''; pageButtonReportStatus.className = 'mb-4 text-sm';}}, duration); }
}

    

// --- Auth Context Ready Handler ---
function authContextIsReady() {
    if (isAuthContextReady) return;
    console.log("audio_admin.js: Authentication context is now marked as ready.");
    isAuthContextReady = true;
    initializePage();
}

// --- Event Listeners ---
// Listener for when the authentication context is ready
// --- Admin Toolbar Button Handlers ---
function setupAdminToolbarButtons() {
    const switchUserButton = document.getElementById('switch-user-button');
    const logoutButton = document.getElementById('logout-button');

    function handleSwitchUser() {
        console.log("Switching user profile. Clearing session and redirecting to auth page for profile selection.");
        // Only set flag to prevent auto-proceed with default user - keep user authenticated
        localStorage.setItem('bravoSkipDefaultUser', 'true');
        console.log('Set bravoSkipDefaultUser flag for profile selection');
        sessionStorage.clear();
        
        // Small delay to ensure localStorage is written before navigation
        setTimeout(() => {
            window.location.href = 'auth.html';
        }, 100);
    }

    function handleLogout() {
        console.log("Logging out. Clearing session and redirecting to auth page for login.");
        // Set both flags to prevent automatic re-login and auto-profile selection
        localStorage.setItem('bravoIntentionalLogout', 'true');
        localStorage.setItem('bravoSkipDefaultUser', 'true');
        console.log('Set bravoIntentionalLogout and bravoSkipDefaultUser flags');
        sessionStorage.clear();
        
        // Small delay to ensure localStorage is written before navigation
        setTimeout(() => {
            window.location.href = 'auth.html';
        }, 100);
    }

    if (switchUserButton) {
        switchUserButton.addEventListener('click', handleSwitchUser);
        console.log("admin_audit_report.js: Switch User button event listener added");
    }
    if (logoutButton) {
        logoutButton.addEventListener('click', handleLogout);
        console.log("admin_audit_report.js: Logout button event listener added");
    }
}

document.addEventListener('adminUserContextReady', () => {
    console.log("user_diary_admin.js: 'adminUserContextReady' event received.");
    authContextIsReady();
});

if (window.adminContextInitializedByInlineScript === true) {
    console.log("user_diary_admin.js: Global flag 'adminContextInitializedByInlineScript' was already true.");
    authContextIsReady();
}

document.addEventListener('DOMContentLoaded', () => {
    console.log("user_diary_admin.js: DOMContentLoaded event.");
    isDomContentLoaded = true;
    initializePage();
    setupAdminToolbarButtons(); // Add toolbar button functionality
});


