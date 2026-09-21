@{
    # One entry per Microsoft 365 cloud edition. tools/Build-CloudScripts.ps1 stamps these
    # values into the script templates in this folder and writes the result to <Folder>/.
    #
    # Sources for the endpoint values:
    #   Exchange Online  https://learn.microsoft.com/powershell/exchange/connect-to-exchange-online-powershell
    #   Microsoft Graph  https://learn.microsoft.com/graph/deployments
    #   Power BI         https://learn.microsoft.com/fabric/enterprise/powerbi/service-government-us-overview
    #
    # ExchangeEnvironmentName / GraphEnvironment are left empty when the cloud uses the
    # worldwide endpoints; the scripts then omit the parameter, exactly as Microsoft documents.

    Commercial = @{
        Folder                  = 'commercial'
        Name                    = 'Commercial'
        Description             = 'Microsoft 365 commercial / worldwide tenants'
        ExchangeEnvironmentName = ''
        GraphEnvironment        = ''
        # Microsoft_365_Copilot, from Microsoft's "Product names and service plan identifiers" reference.
        KnownCopilotSkuIds      = @('639dec6b-bb19-468b-871c-c5c441c4b0cb')
        OrganizationExample     = 'contoso.onmicrosoft.com'
        EntraPortalUrl          = 'https://entra.microsoft.com'
        PurviewPortalUrl        = 'https://purview.microsoft.com'
        PowerBIServiceUrl       = 'https://app.powerbi.com'
    }

    GCC = @{
        Folder                  = 'gcc'
        Name                    = 'GCC'
        Description             = 'Microsoft 365 Government Community Cloud (GCC) tenants'
        # GCC is hosted on the worldwide Exchange Online and Microsoft Graph endpoints.
        ExchangeEnvironmentName = ''
        GraphEnvironment        = ''
        # Community-reported GCC Copilot SKU (upstream README). Not listed in Microsoft's public
        # licensing reference, so the users script also discovers Copilot SKUs from the tenant.
        KnownCopilotSkuIds      = @('a920a45e-67da-4a1a-b408-460d7a2453ce')
        OrganizationExample     = 'contoso.onmicrosoft.com'
        EntraPortalUrl          = 'https://entra.microsoft.com'
        PurviewPortalUrl        = 'https://purview.microsoft.com'
        PowerBIServiceUrl       = 'https://app.powerbigov.us'
    }

    GCCHigh = @{
        Folder                  = 'gcch'
        Name                    = 'GCC High'
        Description             = 'Microsoft 365 Government GCC High tenants'
        ExchangeEnvironmentName = 'O365USGovGCCHigh'
        GraphEnvironment        = 'USGov'
        # No GCC High Copilot SKU ID is published; the users script discovers it from the tenant.
        KnownCopilotSkuIds      = @()
        OrganizationExample     = 'contoso.onmicrosoft.us'
        EntraPortalUrl          = 'https://entra.microsoft.us'
        PurviewPortalUrl        = 'https://purview.microsoft.us'
        PowerBIServiceUrl       = 'https://app.high.powerbigov.us'
    }
}
