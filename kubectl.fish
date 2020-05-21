#!/usr/bin/env fish

set __kubectl_timeout 5s
set __kubectl_list_commands get describe delete
set __kubectl_complete_cache "$HOME/.kube/complete.fish"

# Given a K8s resource name in plural, returns (outputs) the singular form of the word
function __singular_resource
    if string match -qr 'sses$' $argv[1]
        string replace -r 'es$' '' $argv[1]
    else if string match -qr 'ses$' $argv[1]
        string replace -r 's$' '' $argv[1]
    else if string match -qr 'ies$' $argv[1]
        string replace -r 'ies$' 'y' $argv[1]
    else if string match -qr 's$' $argv[1]
        string replace -r 's$' '' $argv[1]
    end
end

# Internal function used to call kubectl with options
function __kubectl
    kubectl --request-timeout $__kubectl_timeout $argv
end

# Returns true if command line in progress ends with the first argument given
function __kubectl_command_ends_with
    if [ (commandline -poc)[-1] = $argv[1] ]
        return 0
    else
        return 1
    end
end

# Get the resource (names) from the resource on the command line or the one given
# ex: kubectl get pods <tab> <-- this returns a list of pod names suitable for autocomplete
function __kubectl_get_resource
    set -l kubectl_opts
    set -l command_line (commandline -poc)

    set -l resource_type
    if [ (count $argv) = 1 ]
        set resource_type $argv[1]
    else
        for resource in $__kubectl_resources
            if contains $resource $command_line
                set resource_type $resource
                break
            end
        end
    end

    # If we're not looking for a namespace, and we have the -n in the command line, filter results to the
    # namespace from `-n <namespace>`
    # TODO: Make this work by looking at which resources are namespaced and which aren't
    if [ "$resource_type" != 'namespace' ]
        if contains -- '-n' $command_line
            set -a kubectl_opts -n $command_line[(math (contains -i -- -n $command_line) + 1)]
        else if contains -- '--namespace' $command_line
            set -a kubectl_opts -n $command_line[(math (contains -i -- --namespace $command_line) + 1)]
        end
    end

    # Return the results, split so that fish will see them correctly for autocomplete
    string split ' ' (__kubectl $kubectl_opts get $resource_type -o jsonpath='{ .items[*].metadata.name }')
end

# Given a Kubectl command to run, (ex. get --help) that returns help-style output, extract the options from it
# and generate completions for the options
function __kubectl_parse_complete_from_help
    # These are applied to every `complete` command ... basically if we're ending --help, then we should filter
    # the generated flags for the kubectl subcommand, ex. "get" for `kubectl get --help`
    set every_complete_args
    if [ $argv[-1] = '--help' ]
        set -a every_complete_args --condition "__fish_seen_subcommand_from $argv[-2]"
    end

    # Run the command and parse the output
    kubectl $argv | perl -ne 's/^\s+//g; next unless m/^-/; print' | while read line
        # Options are in the folloiwng format
        # [<short option>, ]<long option>: <description>
        set opts (string split ', ' -- (string split ': ' -- $line)[1])
        set desc (string join ': ' -- (string split ': ' -- $line)[2..-1])

        # This is used to build up the complete command, start from square one per option
        set complete_args

        for opt in $opts
            if string match -rq '^--' -- $opt # long option
                set -l long_opt (string split '=' (string trim --left -c '-' -- $opt))[1]
                set -a complete_args --long-option $long_opt

                # Check to see if this is a flag or takes an arg
                if not contains -- (string split '=' -- $opt)[2] 'false' 'true'
                    if [ $long_opt = 'filename' ] # filenames complete from file system
                        set -a complete_args --require-parameter
                    else # Everything else completes exclusively from complete suggestions
                        set -a complete_args --exclusive

                        # If the long option is a resource, such as a namespace, lets also get the autocomplete suggestion for the resources
                        if contains -- $long_opt $__kubectl_resources
                            set -a complete_args -a "(__kubectl_get_resource $long_opt)"
                        else if [ $long_opt = 'kustomize' ]
                            set -a complete_args -a '(__fish_complete_directories (commandline -ct))'
                        else if [ $long_opt = 'output' ]
                            set output_formats
                            for format in (string split '|' (string split ' ' (string split ': ' $desc)[2])[1])
                                # echo "processing $format" 1>&2
                                set -a output_formats (string split '.' $format)[1]
                            end

                            echo "$output_formats" 1>&2
                            set -a complete_args -a "$output_formats"

                            set desc (string split '.' $desc)[1]
                        end
                    end
                end
            else # short option
                set -a complete_args --short-option (string trim --left -c '-' -- $opt)
            end
        end

        set -a complete_args --description "$desc"
        complete -c kubectl $every_complete_args $complete_args
    end
end

# If there is no autocomplete file, or if we've been told to regenerate the cache
if [ ! -f $__kubectl_complete_cache ] || [ $__kubectl_regenerate_autocomplete ]
    echo "Generating kubectl autocomplete ..." 1>&2

    # (Re)set cached commands
    set -U __kubectl_commands
    kubectl 2>&1 | grep '^  ' | grep -v kubectl | while read line
        set -l cmd_name (string split -n ' ' $line)[1]
        set -l cmd_desc (string split -n ' ' $line)[2..-1]

        set -U -a __kubectl_commands $cmd_name
    end

    # (Re)set cached resource types
    set -U __kubectl_resources
    kubectl api-resources | while read line;
        set -l resource (string split -n ' ' $line)[1]

        if [ ! $resource = 'NAME' ]
            set -U -a __kubectl_resources $resource
            set -U -a __kubectl_resources (__singular_resource $resource)
        end
    end

    # Erase existing completions and disable file completions for the base command
    complete -c kubectl -e
    complete -c kubectl -f

    # Get universal options from `kubectl options`
    __kubectl_parse_complete_from_help options

    # Get options from first-level subcommands (parsed from the command listing when running `kubectl` by itself)
    kubectl 2>&1 | grep '^  ' | grep -v kubectl | while read line
        set -l cmd_name (string split -n ' ' $line)[1]
        set -l cmd_desc (string split -n ' ' $line)[2..-1]

        complete -c kubectl -f -n 'not __fish_seen_subcommand_from $__kubectl_commands' -a "$cmd_name" -d "$cmd_desc"
        complete -c kubectl -f -n "__fish_seen_subcommand_from $cmd_name" -s h -l help -d "Get help on this command"

        __kubectl_parse_complete_from_help $cmd_name --help
    end

    # Add special completion for kubectl resources on get, describe, and logs
    complete -c kubectl -f -n '__fish_seen_subcommand_from $__kubectl_list_commands && not __fish_seen_subcommand_from $__kubectl_resources' -a "$__kubectl_resources"
    complete -c kubectl -f -n '__fish_seen_subcommand_from $__kubectl_list_commands && __fish_seen_subcommand_from $__kubectl_resources' -a "(__kubectl_get_resource)"
    complete -c kubectl -f -n '__fish_seen_subcommand_from logs && __kubectl_command_ends_with logs' -a "(__kubectl_get_resource pods)"

    # Generate the cache
    complete | grep kubectl > $__kubectl_complete_cache

    # Unset the reset flag
    set -eU __kubectl_regenerate_autocomplete
else
    source $__kubectl_complete_cache
end
