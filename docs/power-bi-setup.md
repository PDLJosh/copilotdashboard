# Power BI setup

The template is the same for every cloud. It reads two local CSV files; it does not connect to
your tenant.

## Verify the template (optional, recommended in regulated environments)

`report/M365 Copilot Audit Report.pbit` is the upstream project's file, unmodified. Confirm your
copy matches the recorded checksum before opening it:

```powershell
(Get-FileHash '.\report\M365 Copilot Audit Report.pbit' -Algorithm SHA256).Hash
Get-Content .\report\SHA256SUMS
```

## Load your data

1. Run both export scripts so that `Copilot_Users.csv` and `Copilot_Events.csv` exist.
2. Open `report\M365 Copilot Audit Report.pbit` in Power BI Desktop.
3. Fill in the three parameters:

   | Parameter | Value | Notes |
   | --- | --- | --- |
   | Copilot Log File Path | `C:\M365CopilotReport\Copilot_Events.csv` | Full path, including the file name |
   | Users Log File Path | `C:\M365CopilotReport\Copilot_Users.csv` | Full path, including the file name |
   | InteractionDurationSec | `30` | Assumed length of one Copilot interaction, used by the "time spent" pages. The audit log does not record duration, so this is an estimate you choose. |

4. Select **Load**. If Power BI asks about privacy levels for the files, choose **Organizational**.
5. **File > Save as** a `.pbix` file. Save it **outside** the repository folder - a `.pbix`
   contains a full copy of your data.

To change a path later: **Home > Transform data > Edit parameters**.

## Refresh

Run the two scripts again, then select **Home > Refresh** in Power BI Desktop. The events script
is incremental, so routine refreshes are quick. To automate the export, see
[scheduling.md](scheduling.md).

## Anonymise employee names

The `Users` table has an `ANONIMOUS` column (spelled that way in the template) that can replace
display names in any visual:

1. Select the **Employee** slicer.
2. In the **Visualizations** pane, remove `EMPLOYEE` from the field well.
3. In the **Data** pane, tick `ANONIMOUS` under `Users`.
4. Repeat for the **Top active users** visual and the top-users visual on the **Trends** page.

Anonymising the visuals does not remove names from the data model. Anyone with the `.pbix` can
still see them in the Data view. If you need to share the file itself with people who must not
see names, remove the columns in **Transform data** first, or share a PDF export instead.

## Custom visuals

The template embeds six custom visuals: Chiclet Slicer, Timeline Slicer, Radar Chart, Table
Heatmap, KPI Donut Chart and Advanced Toggle Switch. If your organisation's Power BI tenant
settings block custom visuals that are not certified or not on your approved list, those visuals
show an error until a Power BI administrator allows them
(**Admin portal > Tenant settings > Power BI visuals**, and **Organizational visuals**).

## Publishing

| Cloud | Publish to | Licensing |
| --- | --- | --- |
| Commercial | https://app.powerbi.com | Pro, Premium Per User, or Premium/Fabric capacity to share |
| GCC | https://app.powerbigov.us | No free licence in government clouds; Pro or above |
| GCC High | https://app.high.powerbigov.us | No free licence in government clouds; Pro or above |

Sign in to Power BI Desktop with an account from the right cloud before you select **Publish**.
If your account exists in more than one cloud, Desktop asks which one to use.

Because the report reads files from a local disk, **scheduled refresh in the Power BI service
needs an [on-premises data gateway](https://learn.microsoft.com/data-integration/gateway/service-gateway-onprem)**
on a machine that can see the CSV files (in government clouds, register the gateway in that
cloud). The simpler pattern is to schedule the export, then refresh and republish from Desktop
when you need updated numbers.

Think about who can see the published report. It shows individual people's activity. Use a
workspace with limited membership, and consider the anonymised view for wider audiences.

## Hosting the app logos yourself

The application slicer shows a logo next to each app. The template does not embed these images;
it holds ten web addresses that point at the upstream project on GitHub, for example:

```
https://raw.githubusercontent.com/BojanBuhac/M365-Copilot-Audit-Report/refs/heads/main/img/logo/Excel.png
```

Power BI downloads the images when the report is displayed. **No tenant data is sent**, but the
PC (or the Power BI service) does make requests to `raw.githubusercontent.com`. If that address
is blocked, or you do not want the dependency, point the template at copies you host:

1. Download the ten PNG files from the upstream
   [`img/logo`](https://github.com/BojanBuhac/M365-Copilot-Audit-Report/tree/main/img/logo) folder:
   `Copilot`, `CopilotStudioAgent`, `Excel`, `Loop`, `Outlook`, `PowerPoint`, `Stream`, `Teams`,
   `Whiteboard`, `Word`.
2. Put them somewhere Power BI can read **without signing in** - for example an internal web
   server. (A SharePoint library will not work, because the images are requested anonymously.)
3. In Power BI Desktop: **Home > Transform data**, select the **Images** query, and select the gear
   icon next to the **Source** step. A small table opens. Replace each `LogoURL` value with your
   address and select **OK**, then **Close & Apply**.
4. Save the file. To reuse the change, **File > Export > Power BI template** and keep that
   `.pbit` for your organisation.

If you skip this and the address is blocked, the report works normally; the logos simply appear
as broken-image icons and the app names are still shown.

## If a visual is empty

| Symptom | Likely cause |
| --- | --- |
| Everything is empty | Wrong file path in the parameters, or the **Period** slicer is outside your data's dates |
| "Has M365 Copilot License" on shows nobody | The users export found no Copilot product - see the `Copilot product` lines in its output and [troubleshooting](troubleshooting.md#every-user-shows-hascopilotlicense--false) |
| Organisation pages are empty | Managers are not populated in Entra ID |
| Departments show as blank | Department is not populated in Entra ID |
| Dates fail to load, or the load reports errors in `TimeStamp` | The events file was produced by a different script on non-English Windows. These scripts always write an English month abbreviation; re-export to a new folder. |
| An app never appears | It may not be available in your cloud yet - see [cloud differences](cloud-differences.md#feature-availability) |
