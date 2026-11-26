<#
.SYNOPSIS
    Patches the clock widget of the scoop-installed YASB, or reverts the patch.

.DESCRIPTION
    YASB ships its code as .pyc files in lib\library.zip. This script downloads
    clock.py for the installed version, patches it and stores it in the zip in
    place of clock.pyc; zipimport compiles it on start.

    - strftime codes also work inside <span> tags of the label
    - calendar popup: one-line date header, holiday line only on holidays,
      month title, weekday row without dots, ISO week number per row

    Run again after every `scoop update yasb`, with YASB stopped. If YASB
    changed a patched region, the script stops before touching anything.

.PARAMETER Revert
    Restores library.zip from the backup.

.PARAMETER DryRun
    Writes the patched clock.py to the temp folder, library.zip stays untouched.
#>
param(
    [switch]$Revert,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Qt paints the week number cells itself, styles.css cannot reach them.
$WeekNumberColor     = '#689d6a'
$WeekNumberPointSize = '8'

$app      = "$HOME\scoop\apps\yasb\current"
$zipPath  = "$app\lib\library.zip"
$backup   = "$zipPath.orig"
$entryPyc = 'core/widgets/yasb/clock.pyc'
$entryPy  = 'core/widgets/yasb/clock.py'

if (-not (Test-Path $zipPath)) { throw "library.zip not found: $zipPath" }

if (-not $DryRun -and (Get-Process yasb -ErrorAction SilentlyContinue)) {
    throw 'YASB is running. Stop it first (start-wm.ps1 -Stop), then run this script again.'
}

if ($Revert) {
    if (-not (Test-Path $backup)) { throw "No backup found: $backup" }
    Copy-Item $backup $zipPath -Force
    Write-Host 'Restored the original library.zip.'
    return
}

$manifest = @("$app\scoop-manifest.json", "$app\manifest.json") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $manifest) { throw "No scoop manifest found in $app" }
$version = (Get-Content $manifest -Raw | ConvertFrom-Json).version
$url = "https://raw.githubusercontent.com/amnweb/yasb/v$version/src/core/widgets/yasb/clock.py"
Write-Host "YASB $version - downloading clock.py"
$source = (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
if ($source -is [byte[]]) { $source = [Text.Encoding]::UTF8.GetString($source) }
$source = $source -replace "`r`n", "`n"

# Each patch replaces the lines from Start up to, not including, the first Until
# after it. Gap is what goes between the new code and Until (default: a blank line).
$patches = @(
    @{
        Name  = 'strftime inside <span> tags'
        Start = '                        active_widgets[widget_index].setText(icon_placeholder)'
        Until = '                else:'
        Gap   = ''
        New   = @'
                        span_text = icon_placeholder
                        span_format = re.search(r"\{(.*)}", span_text)
                        if span_format:
                            try:
                                span_text = span_text.replace(span_format.group(), now.strftime(span_format.group(1)))
                            except Exception:
                                pass
                        active_widgets[widget_index].setText(span_text)
'@
    },
    @{
        Name  = 'date text helpers'
        Start = 'class ClockWidget(BaseWidget):'
        Until = '    validation_schema = ClockConfig'
        Gap   = ''
        New   = @'
def _full_date_text(qlocale: QLocale, qdate: QDate) -> str:
    return qlocale.toString(qdate, QLocale.FormatType.LongFormat)


def _month_title_text(qlocale: QLocale, year: int, month: int) -> str:
    return f"{qlocale.standaloneMonthName(month)} {year}"


class ClockWidget(BaseWidget):
'@
    },
    @{
        Name  = 'popup header'
        Start = '        # Left side: Today Date'
        Until = '        self.calendar = CustomCalendar('
        New   = @'
        date_layout = QVBoxLayout()
        date_layout.setContentsMargins(0, 0, 0, 0)
        date_layout.setSpacing(0)

        datetime_now = datetime.now(ZoneInfo(self._active_tz)) if self._active_tz else datetime.now().astimezone()
        qlocale = QLocale(self._locale) if self._locale else QLocale.system()
        today = QDate(datetime_now.year, datetime_now.month, datetime_now.day)

        self.date_label = QLabel(_full_date_text(qlocale, today))
        self.date_label.setProperty("class", "date-label")
        self.date_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        date_layout.addWidget(self.date_label)

        if self.config.calendar.show_holidays:
            self.holiday_label = QLabel("")
            self.holiday_label.setProperty("class", "holiday-label")
            self.holiday_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
            self.holiday_label.setWordWrap(True)
            date_layout.addWidget(self.holiday_label)
            self.update_holiday_label(today)

        self.month_label = QLabel(_month_title_text(qlocale, today.year(), today.month()))
        self.month_label.setProperty("class", "month-label")
        self.month_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        date_layout.addWidget(self.month_label)
'@
    },
    @{
        Name  = 'weekday row and week numbers'
        Start = '        layout.addWidget(self.calendar)'
        Until = '        if self.config.calendar.extended:'
        New   = @'
        # Own weekday row, since Qt's short day names carry a dot ("Mo.").
        # The labels stretch evenly, matching Qt's equal column widths.
        self.calendar.setHorizontalHeaderFormat(QCalendarWidget.HorizontalHeaderFormat.NoHorizontalHeader)
        self.calendar.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        grid_box = QWidget()
        grid_box.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        grid_layout = QVBoxLayout(grid_box)
        grid_layout.setContentsMargins(0, 0, 0, 0)
        grid_layout.setSpacing(0)
        weekday_row = QHBoxLayout()
        weekday_row.setContentsMargins(0, 0, 0, 0)
        weekday_row.setSpacing(0)
        header_texts = [""] if self.config.calendar.show_week_numbers else []
        first_day = self.calendar.firstDayOfWeek().value
        for i in range(7):
            day = (first_day - 1 + i) % 7 + 1
            header_texts.append(qlocale.dayName(day, QLocale.FormatType.ShortFormat).rstrip("."))
        for text in header_texts:
            cell = QLabel(text)
            cell.setProperty("class", "weekday-label")
            cell.setAlignment(Qt.AlignmentFlag.AlignCenter)
            cell.setSizePolicy(QSizePolicy.Policy.Ignored, QSizePolicy.Policy.Preferred)
            weekday_row.addWidget(cell, 1)
        grid_layout.addLayout(weekday_row)
        if self.config.calendar.show_week_numbers:
            from PyQt6.QtGui import QFont, QTextCharFormat

            self.calendar.setVerticalHeaderFormat(QCalendarWidget.VerticalHeaderFormat.ISOWeekNumbers)
            week_format = QTextCharFormat()
            week_format.setBackground(QColor(0, 0, 0, 0))
            week_format.setForeground(QColor("__WEEK_FG__"))
            week_format.setFontWeight(QFont.Weight.Normal)
            week_format.setFontPointSize(__WEEK_PT__)
            self.calendar.setHeaderTextFormat(week_format)
        grid_layout.addWidget(self.calendar)
        date_layout.addWidget(grid_box)
        layout.addLayout(date_layout)
'@
    },
    @{
        Name  = 'month title follows the calendar page'
        Start = '    def update_month_label(self, year: int, month: int) -> None:'
        Until = '    def update_selected_date(self, date: QDate):'
        New   = @'
    def update_month_label(self, year: int, month: int) -> None:
        qlocale = QLocale(self._locale) if self._locale else QLocale.system()
        self.month_label.setText(_month_title_text(qlocale, year, month))
'@
    },
    @{
        Name  = 'header follows the selected date'
        Start = '    def update_selected_date(self, date: QDate):'
        Until = '    def update_week_label(self, qdate: QDate):'
        New   = @'
    def update_selected_date(self, date: QDate):
        qlocale = QLocale(self._locale) if self._locale else QLocale.system()
        self.date_label.setText(_full_date_text(qlocale, date))
        self.month_label.setText(_month_title_text(qlocale, date.year(), date.month()))
        if self.config.calendar.show_holidays:
            self.update_holiday_label(date)
'@
    },
    @{
        Name  = 'holiday line only on holidays'
        Start = '    def update_holiday_label(self, qdate: QDate):'
        Until = '    def get_country_code(self) -> str | None:'
        New   = @'
    def update_holiday_label(self, qdate: QDate):
        country = _supported_country(self._country_code)
        holiday_name = None
        if country:
            h = _get_cached_country_holidays(country, qdate.year(), self._subdivision)
            holiday_name = h.get(date(qdate.year(), qdate.month(), qdate.day()))
        self.holiday_label.setText(holiday_name or "")
        self.holiday_label.setVisible(bool(holiday_name))
'@
    }
)

function Set-Region([string]$Text, [hashtable]$Patch) {
    $startNeedle = "`n$($Patch.Start)`n"
    $s = $Text.IndexOf($startNeedle, [StringComparison]::Ordinal)
    if ($s -lt 0) { throw "Patch '$($Patch.Name)': start line not found. YASB changed this code, the patch needs an update." }
    if ($Text.IndexOf($startNeedle, $s + 1, [StringComparison]::Ordinal) -ge 0) {
        throw "Patch '$($Patch.Name)': start line is not unique."
    }
    $u = $Text.IndexOf("`n$($Patch.Until)`n", $s + 1, [StringComparison]::Ordinal)
    if ($u -lt 0) { throw "Patch '$($Patch.Name)': end line not found. YASB changed this code, the patch needs an update." }
    $new = ($Patch.New -replace "`r`n", "`n").TrimEnd("`n") + "`n"
    $gap = if ($Patch.ContainsKey('Gap')) { $Patch.Gap } else { "`n" }
    return $Text.Substring(0, $s + 1) + $new + $gap + $Text.Substring($u + 1)
}

$patched = $source
foreach ($p in $patches) {
    $patched = Set-Region $patched $p
    Write-Host "  patched: $($p.Name)"
}
$patched = $patched.Replace('__WEEK_FG__', $WeekNumberColor).Replace('__WEEK_PT__', $WeekNumberPointSize)
$patched = "# Patched locally by .config/yasb/patches/apply-yasb-patches.ps1 (YASB $version)`n" + $patched

if ($DryRun) {
    $out = Join-Path ([IO.Path]::GetTempPath()) "yasb-clock-patched-$version.py"
    [IO.File]::WriteAllText($out, $patched, (New-Object Text.UTF8Encoding $false))
    Write-Host "Dry run, library.zip untouched. Patched source: $out"
    return
}

# Always patch the untouched zip, so running the script twice is safe.
if (Test-Path $backup) {
    Copy-Item $backup $zipPath -Force
} else {
    Copy-Item $zipPath $backup
    Write-Host "Backup: $backup"
}

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Update)
try {
    $pyc = $zip.GetEntry($entryPyc)
    if (-not $pyc) { throw "$entryPyc not found in library.zip" }
    $pyc.Delete()
    $existing = $zip.GetEntry($entryPy)
    if ($existing) { $existing.Delete() }
    $entry = $zip.CreateEntry($entryPy, [IO.Compression.CompressionLevel]::Optimal)
    $writer = New-Object IO.StreamWriter($entry.Open(), (New-Object Text.UTF8Encoding $false))
    try { $writer.Write($patched) } finally { $writer.Dispose() }
} finally {
    $zip.Dispose()
}
Write-Host 'Patched library.zip. Start YASB again to load it.'
