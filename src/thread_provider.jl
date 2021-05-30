using Preferences
function get_provider()
    default_provider = "Threads"

    # Load the preference
    provider = @load_preference("provider", default_provider)

    # Ensure the provider matches one of the ones we support
    if provider ∉ ("Threads", "Polyester")
        @error("Invalid Threads setting \"$(provider)\"; valid settings include [\"Threads\", \"Polyester\"], defaulting to \"Threads\"")
        provider = default_provider
    end
    return provider
end

# Read in preferences, see if any users have requested a particular backend
const threads_provider = get_provider()

"""
    set_provider!(provider; export_prefs::Bool = false)
Convenience wrapper for setting the Threads provider.  Valid values include `"Threads"`, `"Polyester"`.
Also supports `Preferences` sentinel values `nothing` and `missing`; see the docstring for
`Preferences.set_preferences!()` for more information on what these values mean.
"""
function set_provider!(provider; export_prefs::Bool = false)
    if provider !== nothing && provider !== missing && provider ∉ ("Threads", "Polyester")
        throw(ArgumentError("Invalid provider value '$(provider)'; valid settings include [\"Threads\", \"Polyester\"]"))
    end
    set_preferences!(@__MODULE__, "provider" => provider; export_prefs, force = true)
    if provider != threads_provider
        # Re-fetch to get default values in the event that `nothing` or `missing` was passed in.
        provider = get_provider()
        @info("Threads provider changed; restart Julia for this change to take effect", provider)
    end
end
