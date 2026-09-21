# Cloud differences

Everything that differs between the editions, and where each value comes from.

## Which cloud am I in?

| Clue | Commercial | GCC | GCC High | DoD |
| --- | --- | --- | --- | --- |
| Sign-in page | login.microsoftonline.com | login.microsoftonline.com | login.microsoftonline**.us** | login.microsoftonline**.us** |
| Initial tenant domain | `.onmicrosoft.com` | `.onmicrosoft.com` | `.onmicrosoft.us` | `.onmicrosoft.us` |
| SharePoint address | `.sharepoint.com` | `.sharepoint.com` | `.sharepoint.us` | `.sharepoint-mil.us` |
| Plans | Business, E3, E5, ... | G1, G3, G5 | GCC High plans, bought through an authorised reseller | DoD plans |

GCC is easy to mistake for commercial because the addresses are the same. If your licenses are
"G" plans and you sign in at `.com`, you are in GCC.

## Values used by the scripts

| | Commercial | GCC | GCC High |
| --- | --- | --- | --- |
| Folder | [`commercial/`](../commercial/README.md) | [`gcc/`](../gcc/README.md) | [`gcch/`](../gcch/README.md) |
| `Connect-ExchangeOnline -ExchangeEnvironmentName` | *(omitted)* | *(omitted)* | `O365USGovGCCHigh` |
| `Connect-MgGraph -Environment` | *(omitted = Global)* | *(omitted = Global)* | `USGov` |
| Microsoft Graph endpoint | graph.microsoft.com | graph.microsoft.com | graph.microsoft.us |
| Built-in Copilot product ID | `639dec6b-bb19-468b-871c-c5c441c4b0cb` | `a920a45e-67da-4a1a-b408-460d7a2453ce` | *(none)* |
| Copilot product discovery by service plan | Yes | Yes | Yes |
| Teams address recognised in events | teams.microsoft.com | teams.microsoft.com | teams.microsoft.us |
| `-Organization` / `-TenantId` example | contoso.onmicrosoft.com | contoso.onmicrosoft.com | contoso.onmicrosoft.us |

All of these live in one file, [`src/clouds.psd1`](../src/clouds.psd1).

## Addresses you use yourself

| | Commercial | GCC | GCC High |
| --- | --- | --- | --- |
| Microsoft Entra admin center | entra.microsoft.com | entra.microsoft.com | entra.microsoft.us |
| Azure portal (app registrations) | portal.azure.com | portal.azure.com | portal.azure.us |
| Microsoft Purview portal | purview.microsoft.com | purview.microsoft.com | purview.microsoft.us |
| Power BI service | app.powerbi.com | app.powerbigov.us | app.high.powerbigov.us |
| Power BI free licence available | Yes | No | No |

## About the Copilot product IDs

The upstream script decides who is licensed by comparing each user's licenses with a single
product ID. That is the weak point in government clouds:

- The **commercial** ID is in Microsoft's public
  [product names and service plan identifiers](https://learn.microsoft.com/entra/identity/users/licensing-service-plan-reference)
  reference.
- The **GCC** ID was reported by the community in the upstream project's README. It is not in
  Microsoft's public reference.
- **No GCC High ID is published.**

So these scripts do not depend on the ID. They read the products in *your* tenant
(`Get-MgSubscribedSku`) and treat any product that contains a service plan named
`M365_COPILOT*` as Microsoft 365 Copilot. A user counts as licensed when at least one of those
service plans is enabled for them. The script prints what it found, so you can confirm it:

```
Copilot product: 639dec6b-bb19-468b-871c-c5c441c4b0cb  Microsoft_365_Copilot  (known ID)
Copilot product: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  <a suite that includes Copilot>  (discovered)
```

If your cloud names its Copilot service plans differently and nothing is found, the script says
so and lists candidate products; pass the right one with `-CopilotSkuId`. Please also open an
issue so the pattern can be improved.

## Feature availability

Copilot features reach government clouds later than commercial ones, so some apps may have no
rows in a government tenant's report. Microsoft's
[Copilot service description](https://learn.microsoft.com/office365/servicedescriptions/office-365-platform-service-description/microsoft-365-copilot#feature-availability)
is the authoritative, current list.

## DoD

DoD is not packaged as a folder because it has not been requested or tested, but the change is
small. Copy the `GCCHigh` block in [`src/clouds.psd1`](../src/clouds.psd1) to a new `DoD` block
with these values and run `tools\Build-CloudScripts.ps1`:

| Setting | DoD value |
| --- | --- |
| `Folder` | `dod` |
| `ExchangeEnvironmentName` | `O365USGovDoD` |
| `GraphEnvironment` | `USGovDoD` (dod-graph.microsoft.us) |
| Power BI service | app.mil.powerbigov.us |

The event classification already recognises `dod.teams.microsoft.us`. Note that Microsoft lists
unified audit log reporting differences for DoD; check that `Search-UnifiedAuditLog` returns
`CopilotInteraction` records in your tenant before relying on it.

## Sources

- Exchange Online environments: [Connect to Exchange Online PowerShell](https://learn.microsoft.com/powershell/exchange/connect-to-exchange-online-powershell)
- Microsoft Graph environments: [National cloud deployments](https://learn.microsoft.com/graph/deployments) and [Get-MgEnvironment](https://learn.microsoft.com/powershell/microsoftgraph/authentication-commands#use-get-mgenvironment)
- Power BI addresses and licensing: [Power BI for US government customers](https://learn.microsoft.com/fabric/enterprise/powerbi/service-government-us-overview)
- Copilot in government clouds: [Microsoft 365 Copilot for US government](https://learn.microsoft.com/microsoft-365/copilot/gov-overview)
- Audit records for Copilot: [Audit logs for Copilot and AI applications](https://learn.microsoft.com/purview/audit-copilot)
- The 50,000-record search limit: [Search-UnifiedAuditLog](https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog)
