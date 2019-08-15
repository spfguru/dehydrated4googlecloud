#!/usr/bin/env bash

function deploy_challenge {
    # This hook is called once for every domain that needs to be
    # validated, including any alternative names you may have listed.
    #
    # Parameters:
    # - DOMAIN
    #   The domain name (CN or subject alternative name) being
    #   validated.
    # - TOKEN_FILENAME
    #   The name of the file is irrelevant for the DNS challenge, yet still provided 
    # - TOKEN_VALUE
    #   The token value that needs to be served for validation. For DNS
    #   validation, this is what you want to put in the _acme-challenge
    #   TXT record. For HTTP validation it is the value that is expected
    #   be found in the $TOKEN_FILENAME file.
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"

    echo;
    echo "Deploying challenge for domain $DOMAIN"

    managedZones=`gcloud dns managed-zones list --format="value(dnsName,name)"`
    managedZones=${managedZones//$'\t'/,}

    mainDomainFound=false
    for managedZone in $managedZones; do 
        IFS=$',' read dnsDomain zonename <<< "$managedZone"

        if [[ "$DOMAIN." == "$dnsDomain" || "$DOMAIN." == *".$dnsDomain" ]]; then
            mainDomainFound=true
            break
        fi
    done

    if ! $mainDomainFound ; then
        echo "Domain $DOMAIN not hosted in this Google Cloud DNS project."
        exit 1
    fi

    test -f transaction.yaml && rm transaction.yaml
    gcloud dns record-sets transaction start --zone $zonename

    # remove token, if it exists
    existingRecord=`gcloud dns record-sets list --name "_acme-challenge.$DOMAIN." --type TXT --zone $zonename --format='value(name,rrdatas[0],ttl)'`
    existingRecord=${existingRecord//$'\t'/,}
    IFS=$',' read existingName existingRrdata existingTtl <<< "$existingRecord"

    # Replace threefold """ with single "
    existingRrdata=${existingRrdata//$'"""'/''}

    if [ "$existingName" == "_acme-challenge.$DOMAIN." ]; then
        gcloud dns record-sets transaction remove --name $existingName --type TXT --ttl $existingTtl --zone $zonename -- "$existingRrdata" 
    fi

    gcloud dns record-sets transaction add --name "_acme-challenge.$DOMAIN." --ttl 300 --type TXT --zone $zonename -- "$TOKEN_VALUE" 
    gcloud dns record-sets transaction describe --zone $zonename

    changeID=$(gcloud dns record-sets transaction execute --zone $zonename --format='value(id)')

    status=$(gcloud dns record-sets changes describe $changeID --zone $zonename --format='value(status)')
    echo -n "Checking execution status of this transaction (can easily take 2-5 minutes): "
    until [[ "$status" = "done" ]]; do
        echo -n "$status"
        sleep 1
        echo -n "."
        sleep 1
        echo -n "."
        sleep 1
        echo -n "."
        sleep 1
        echo -n "."
        status=$(gcloud dns record-sets changes describe $changeID --zone $zonename --format='value(status)')
    done
    echo "done"

    # Even if the transaction is executed, the results may not be available in the DNS servers yet
    echo "Verifying results on live DNS servers:"
    for nameserver in $(dig $dnsDomain NS +short); do 
        echo -n "$nameserver " 
        nsresult=$(dig _acme-challenge.$DOMAIN TXT @$nameserver +short)
        # nsresult comes with the TXT RR in double quotes - remove those
        nsresult=${nsresult//$'"'/''}
        until [[ "$nsresult" = "$TOKEN_VALUE" ]]; do
            echo -n "pending"
            sleep 1
            echo -n "."
            sleep 1
            echo -n "."
            sleep 1
            echo -n "."
            sleep 1
            echo -n "."
            nsresult=$(dig _acme-challenge.$DOMAIN TXT @$nameserver +short)
            # nsresult comes with the TXT RR in double quotes - remove those
            # TODO DRY: move to dedicated function
            nsresult=${nsresult//$'"'/''}
        done
        echo "done"
    done

    echo "Sleeping for another 30 seconds to avoid timing conflicts"
    sleep 30
}


function clean_challenge {
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"

    echo;
    echo "Cleaning challenge for domain $DOMAIN"
    # This hook is called after attempting to validate each domain,
    # whether or not validation was successful. Here you can delete
    # files or DNS records that are no longer needed.
    #
    # The parameters are the same as for deploy_challenge.

    # TODO DRY: move the following block into a function!
    managedZones=`gcloud dns managed-zones list --format="value(dnsName,name)"`
    managedZones=${managedZones//$'\t'/,}

    mainDomainFound=false
    for managedZone in $managedZones; do 
        IFS=$',' read dnsDomain zonename <<< "$managedZone"

        if [[ "$DOMAIN." == "$dnsDomain" || "$DOMAIN." == *".$dnsDomain" ]]; then
            mainDomainFound=true
            break
        fi
    done

    if ! $mainDomainFound ; then
        echo "Domain $DOMAIN not hosted in this Google Cloud DNS project."
        exit 1
    fi

    test -f transaction.yaml && rm transaction.yaml
    gcloud dns record-sets transaction start --zone $zonename

    existingRecord=`gcloud dns record-sets list --name "_acme-challenge.$DOMAIN." --type TXT --zone $zonename --format='value(name,rrdatas[0],ttl)'`
    existingRecord=${existingRecord//$'\t'/,}
    IFS=$',' read existingName existingRrdata existingTtl <<< "$existingRecord"

    # Replace threefold """ with singe "
    existingRrdata=${existingRrdata//$'"""'/''}

    gcloud dns record-sets transaction remove --name $existingName --type TXT --ttl $existingTtl --zone $zonename -- "$existingRrdata"
    gcloud dns record-sets transaction execute --zone $zonename
}


function deploy_cert {
    # This hook is called once for each certificate that has been
    # produced. Here you might, for instance, copy your new certificates
    # to service-specific locations and reload the service.
    #
    # Parameters:
    # - DOMAIN
    #   The primary domain name, i.e. the certificate common
    #   name (CN).
    # - KEYFILE
    #   The path of the file containing the private key.
    # - CERTFILE
    #   The path of the file containing the signed certificate.
    # - FULLCHAINFILE
    #   The path of the file containing the full certificate chain.
    # - CHAINFILE
    #   The path of the file containing the intermediate certificate(s).
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}"

    echo;
    echo "Deploying certificate for $DOMAIN from $KEYFILE and $FULLCHAINFILE"
    canonicalname=$(sed -e 's:\.:-:g' -e 's:\*:wildcard:g' <<< $DOMAIN)
    certname=$canonicalname-$(date +%s)
    httpsproxyname=https-proxy-$canonicalname

    gcloud beta compute ssl-certificates create $certname --certificate $FULLCHAINFILE --private-key $KEYFILE --description "$DOMAIN"


    if [ "$httpsproxyname" == "$(gcloud compute target-https-proxies describe $httpsproxyname --format='value(name)' &2> /dev/null)" ]; then
        gcloud compute target-https-proxies update $httpsproxyname --ssl-certificates $certname
    else
        echo "====================================================================================================="
        echo "WARNING: Unable to find https target proxy named '$httpsproxyname' - no automatic update performed";
        echo "YOU have to update your target proxy manually and set the SSL certificate to '$certname'"
        echo "Go to https://console.cloud.google.com/networking/loadbalancing/advanced/targetHttpsProxies/"
        echo "OR run the following command: (change \$MY_HTTPS_PROY_NAME to your actual proxy name)"
        echo "gcloud compute target-https-proxies update \$MY_HTTPS_PROY_NAME --ssl-certificates $certname"
        echo "====================================================================================================="
    fi
}

function unchanged_cert {
    # This hook is called once for each certificate that is still valid at least 30 days
    #
    # Parameters:
    # - DOMAIN
    #   The primary domain name, i.e. the certificate common
    #   name (CN).
    # - KEYFILE
    #   The path of the file containing the private key.
    # - CERTFILE
    #   The path of the file containing the signed certificate.
    # - FULLCHAINFILE
    #   The path of the file containing the full certificate chain.
    # - CHAINFILE
    #   The path of the file containing the intermediate certificate(s).
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}"

    echo "Certificate for domain $DOMAIN is still valid - no action taken"
}

HANDLER="$1"; shift
if [[ "${HANDLER}" =~ ^(deploy_challenge|clean_challenge|deploy_cert|unchanged_cert)$ ]]; then
  "$HANDLER" "$@"
fi
