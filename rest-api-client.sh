#!/bin/bash
# ======================================================================
#
# REST API CLIENT USING CURL
#
# REQUIREMENTS
# - Bash (Linux or MS Windows i.e with Cygwin)
# - curl
# - sha1sum (optional; for export functionality with AUTOFILE only)
# ----------------------------------------------------------------------
# (1) source this script
# (2) enter "http.help" to get a list of available commands
# ----------------------------------------------------------------------
# 2020-02-07  v0.2  axel.hahn@iml.unibe.ch  BETABETA
# 2020-02-12  v0.4  axel.hahn@iml.unibe.ch  Caching
# 2020-03-02  v0.5  axel.hahn@iml.unibe.ch  a few more response check functions
# ======================================================================

# --- fetch incoming params
  RestApiCfg=$1
  RestApiMethod=$2
  ApiUrl=$3
  Body="$4"

  http_cfg__about="Bash REST API client v0.5"
  typeset -i http_cfg__debug=0
  typeset -i http_cfg__cacheTtl=0
  http_cfg__cacheDir=/var/tmp/http-cache
  http_cfg__UA="${http_cfg__about}"
  http_cfg__prjurl="https://git-repo.iml.unibe.ch/iml-open-source/bash-rest-api-client"

# --- curl meta infos to collect
#     see variables in man curl --write-out param
  curlMeta="\
    http_code \
    http_connect \
    local_ip \
    local_port \
    num_connects \
    num_redirects \
    redirect_url \
    remote_ip \
    remote_port \
    size_download \
    size_header \
    size_request \
    size_upload \
    speed_download \
    speed_upload \
    ssl_verify_result \
    time_appconnect \
    time_connect \
    time_namelookup \
    time_pretransfer \
    time_redirect \
    time_starttransfer \
    time_total \
    url_effective \
"


# ----------------------------------------------------------------------
#
# functions
#
# ----------------------------------------------------------------------

  # ......................................................................
  #
  # write a debug message to STDERR
  # Do no not change the prefix - is is read in inc_functions
  #
  # params  strings  output message
  function http._wd(){
    if [ $http_cfg__debug -gt 0 ]; then
      echo -e "\e[33m# RESTAPI::DEBUG $*\e[0m" >&2
    fi
  }

  # ......................................................................
  #
  # write an error message to STDERR
  # Do no not change the prefix - is is read in inc_functions
  #
  # params  strings  output message
  function http._we(){
    echo -e "\e[31m# RESTAPI::ERROR $*\e[0m" >&2
  }

  function http(){
  cat <<EOH

$http_cfg__about

A REST API Client with curl

Enter http.help to show all commands.

EOH
    # $0 is not the current file if we source a script
    # grep "function http.[a-z]" $0 | sort
  }

  function http.init(){

    which curl >/dev/null || http.quit

    # request vars

    http_req__auth=
    http_req__auth=
    http_req__body=
    http_req__method=GET
    http_req__url=
    http_req__fullurl=
    http_req__docs=

    http_req__dataprefix="RESTAPICLIENTMETADATA_`date +%s`_$$"
    local writevar=
    for myvar in $curlMeta
    do
      writevar="${writevar}|${myvar}:%{${myvar}}"
    done
    http_curl__writeout="\\n${http_req__dataprefix}${writevar}\\n"

    # cache
    http_req__mode=undefined
    http_cfg__cacheTtl=0
    http_cfg__cacheFile=

    # response
    http_resp__all=
    http_resp__neutral=
    mkdir ${http_cfg__cacheDir} 2>/dev/null
    chmod 777 ${http_cfg__cacheDir} 2>/dev/null
  }

  # execute the request
  # param  string  optional: full url
  function http.makeRequest(){
    http._wd "${FUNCNAME[0]}($1)"

    # --- handle optional prams
    if [ $# -ne 0 ]; then
      echo $1 | grep "^[A-Z]*$" >/dev/null
      if [ $? -eq 0 ]; then
        http.setMethod "$1"
        shift 1
      fi
      http.setUrl "$1"
      http.setBody "$2"
    fi
    # test -z "$1" || http.setFullUrl "$1"

    # --- detect caching
    http_req__mode=REQUEST
    useCache=0
    makeRequest=1
    if [ $http_cfg__cacheTtl -gt 0 -a "${http_req__method}" = "GET" ]; then
      useCache=1
      test -z "${http_cfg__cacheFile}" && http_cfg__cacheFile=`http._genOutfilename "${http_cfg__cacheDir}/AUTOFILE"`
      if [ -f "${http_cfg__cacheFile}" ]; then
        http.responseImport "${http_cfg__cacheFile}"
        typeset -i local iAge=`http.getRequestAge`
        http._wd "INFO: Age of cache is $iAge sec  - vs TTL $http_cfg__cacheTtl sec - file $http_cfg__cacheFile"
        if [ $iAge -gt 0 -a $iAge -lt $http_cfg__cacheTtl ]; then
          http._wd "INFO: Using cache"
          makeRequest=0
          http_req__mode=CACHE
        else
          http._wd "INFO: Cache file will be updated after making the request"
          rm -f "${http_cfg__cacheFile}" 2>/dev/null
        fi
      fi
    fi


    # --- make the request
    if [ $makeRequest -eq 1 ]; then
      http_req__start=`date +%s`
      http._wd "${FUNCNAME[0]}($1) ${http_req__method} ${http_req__fullurl}"
      http_resp__all=$(
        if [ -z "${http_req__body}" ]; then
          curl -k -s \
            -A "${http_cfg__UA}" \
            -w "${http_curl__writeout}" \
            -H 'Accept: application/json' \
            ${http_req__auth} \
            -i "${http_req__fullurl}" \
            -X "${http_req__method}"
        else
          curl -k -s \
            -A "${http_cfg__UA}" \
            -w "${http_curl__writeout}" \
            -H 'Accept: application/json' \
            ${http_req__auth} \
            -i "${http_req__fullurl}" \
            -X "${http_req__method}" \
            -d "${http_req__body}"
        fi
        ) || http.quit
      http._wd "OK - Curl finished the http request ... processing data"
      http_resp__neutral=`http._fetchAllAndReformat`
      if [ $useCache -eq 1 ]; then
        http._wd "INFO: writing cache ..."
        http.responseExport "${http_cfg__cacheFile}"
      fi
    fi
    http._wd "Request function finished; Code `http.getStatuscode`"
  }

  # ......................................................................
  #
  # show error message with last return code and quit with this exitcode
  # no params
  function http.quit(){
    http._wd "${FUNCNAME[0]}($1)"
    rc=$?
    echo >&2
    echo -e "\e[31m# ERROR: command FAILED with rc $rc. \e[0m" >&2
    if [ ! -z "${RestApiDocs}" ]; then
      echo "HINT: see ${RestApiDocs}" >&2
    fi
    # dont make exit in a sourced file
    # exit $rc
  }


  # load a config file
  function http.loadcfg(){
    http._wd "${FUNCNAME[0]}($1) !!! DEPRECATED !!!"
    # reset expected vars from config
    RestApiUser=
    RestApiPassword=
    RestApiBaseUrl=
    RestApiDocs=

    # source config file
    . "${1}" || http.quit

    # set "internal" vars
    if [-z "$RestApiPassword" ]; then
      http.setAuth "$RestApiUser:$RestApiPassword"
    else
      http.setAuth
    fi
    http.setBaseUrl "${RestApiBaseUrl}"
    http.setDocs "${RestApiDocs}"
  }

  # ======================================================================
  # GETTER
  # ======================================================================
  function http._fetchResponseHeaderOrBody(){
    http._wd "${FUNCNAME[0]}($1)"
    local isheader=true

    # keep leading spaces
    IFS=''

    echo "${http_resp__all}" | grep -v "${http_req__dataprefix}" | while read -r line; do
      if $isheader; then
        if [[ $line = $'\r' ]]; then
            isheader=false
        else
          test "$1" = "header" && echo $line
        fi
      else
        # body="$body"$'\n'"$line"
        test "$1" = "body" && echo $line
      fi
    done
  }
  function http._fetchResponseData(){
    http._wd "${FUNCNAME[0]}($1)"
    echo "${http_resp__all}" | sed "s#${http_req__dataprefix}#\n${http_req__dataprefix}#" | grep "${http_req__dataprefix}" | tail -1 | cut -f 2- -d "|" | sed "s#|#\n#g" | grep -v "${http_req__dataprefix}" | while read -r line; do
      echo $line
    done
  }
  function http._fetchAllAndReformat(){
    http._wd "${FUNCNAME[0]}($1)"
    IFS=''
    line="#------------------------------------------------------------"

    echo "#_META_|about:$http_cfg__about"
    echo "#_META_|host:`hostname -f`"
    echo $line
    echo "#_REQUEST_|fullurl:$http_req__fullurl"
    echo "#_REQUEST_|method:$http_req__method"
    echo "#_REQUEST_|time:`date`"
    echo "#_REQUEST_|timestamp:`date +%s`"
    echo "#_REQUEST_|auth:`echo $http_req__auth | sed 's#:.*#:xxxxxxxx#'`"
    echo "#_REQUEST_|body:$http_req__body"
    echo "#_REQUEST_|baseurl:$http_req__baseurl"
    echo "#_REQUEST_|url:$http_req__url"
    echo "#_REQUEST_|docs:$http_req__docs"
    echo $line
    http._fetchResponseHeaderOrBody header  | sed "s,^,#_HEADER_|,g"
    echo $line
    http._fetchResponseData                 | sed "s,^,#_DATA_|,g"
    echo $line
    http._fetchResponseHeaderOrBody body    | sed "s,^,#_BODY_|,g"
    echo $line END
  }

  function http._getFilteredResponse(){
    http._wd "${FUNCNAME[0]}($1)"
    echo "${http_resp__neutral}" | grep "^#_${1}_|"  | cut -f 2- -d "|"
  }

  # ---------- PUBLIC REQUEST GETTER

  function http.getRequestTs(){
    http._wd "${FUNCNAME[0]}($1)"
    http._getFilteredResponse REQUEST | grep "^timestamp" | cut -f 2 -d ":"
  }

  # get age of the response in sec.
  # It is especially useful after responseImport
  function http.getRequestAge(){
    http._wd "${FUNCNAME[0]}($1)"
    typeset -i local iAge=`date +%s`-`http.getRequestTs`
    echo $iAge
  }

  # ---------- PUBLIC RESPONSE GETTER

  # get response body
  function http.getResponse(){
    http._wd "${FUNCNAME[0]}($1)"
    http._getFilteredResponse BODY
  }
  # get curl data of this request with status, transferred bytes, speed, ...
  function http.getResponseData(){
    http._wd "${FUNCNAME[0]}($1)"
    http._getFilteredResponse DATA
  }
  # get response header
  function http.getResponseHeader(){
    http._wd "${FUNCNAME[0]}($1)"
    http._getFilteredResponse HEADER
  }

  # get raw response (not available after import)
  function http.getResponseRaw(){
    http._wd "${FUNCNAME[0]}($1)"
    echo "${http_resp__all}"
  }

  # get Http status as string OK|Redirect|Error
  function http.getStatus(){
    http._wd "${FUNCNAME[0]}($1)"
    http.isOk       >/dev/null && echo OK
    http.isRedirect >/dev/null && echo Redirect
    http.isError    >/dev/null && echo Error
  }

  # get Http status code of the request as 3 digit number
  function http.getStatuscode(){
    http._wd "${FUNCNAME[0]}($1)"
    local _filter=$1
    http.getResponseData | grep "^http_code:" | cut -f 2 -d ":"
  }

  # was response a 2xx status code?
  # output is a statuscode if it matches ... or empty
  # Additionally you can verify the return code
  # $? -eq 0 means YES
  # $? -ne 0 means NO
  function http.isOk(){
    http._wd "${FUNCNAME[0]}($1)"
    http.getStatuscode | grep '2[0-9][0-9]'
  }
  # was the repsonse a redirect?
  function http.isRedirect(){
    http._wd "${FUNCNAME[0]}($1)"
    http.getStatuscode | grep '3[0-9][0-9]'
  }

  # was the repsonse a client error (4xx or 5xx)
  function http.isError(){
    http._wd "${FUNCNAME[0]}($1)"
    http.getStatuscode | grep '[45][0-9][0-9]'
  }
  # was the repsonse a client error (4xx)
  function http.isClientError(){
    http._wd "${FUNCNAME[0]}($1)"
    http.getStatuscode | grep '4[0-9][0-9]'
  }
  # was the repsonse a client error (5xx)
  function http.isServerError(){
    http._wd "${FUNCNAME[0]}($1)"
    http.getStatuscode | grep '5[0-9][0-9]'
  }


  # dump information about request and response
  function http.dump(){
    http._wd "${FUNCNAME[0]}($1)"
    http.responseExport
  }

  # ======================================================================
  # Import/ Export
  # ======================================================================

  # helper to replace "AUTOFILE" with something uniq using full url
  # param  string  import or export filename
  function http._genOutfilename(){
    http._wd "${FUNCNAME[0]}($1)"
    echo $1 | grep "AUTOFILE" >/dev/null
    if [ $? -ne 0 ]; then
      echo $1
    else
      local sum=`echo ${http_req__fullurl} | sha1sum `
      local autofile=`echo "${sum}__${http_req__fullurl}" | sed "s#[^a-z0-9]#_#g"`
      echo $1 | sed "s#AUTOFILE#${autofile}#"
    fi
  }


  # export to a file
  function http.responseExport(){
    http._wd "${FUNCNAME[0]}($1)"
    if [ -z $1 ]; then
      echo "${http_resp__neutral}"
    else
      local outfile=`http._genOutfilename "$1"`
      http._wd "${FUNCNAME[0]}($1) writing to outfile $outfile"
      echo "${http_resp__neutral}" >$outfile
    fi
  }

  # import a former response from a file
  function http.responseImport(){
    http._wd "${FUNCNAME[0]}($1)"
    local infile=`http._genOutfilename "$1"`
    if [ -r "${infile}" ]; then
      grep "^#_META_|about:$http_cfg__about" "${infile}" >/dev/null
      if [ $? -eq 0 ]; then
         http_resp__neutral=`cat "${infile}"`
      else
         echo "ERROR: Ooops [${infile}] does not seem to be an export dump."
         http.quit
      fi
    else
      echo "ERROR: Ooops the file [${infile}] is not readable."
      http.quit
    fi
  }
  # delete an exported file; this is especially useful if you use
  # AUTOFILE functionality
  function http.responseDelete(){
    http._wd "${FUNCNAME[0]}($1)"
    local infile=`http._genOutfilename "$1"`
    if [ -r "${infile}" ]; then
      grep "^#_META_|about:$http_cfg__about" "${infile}" >/dev/null
      if [ $? -eq 0 ]; then
        rm -f "${infile}"
        if [ $? -eq 0 ]; then
          http._wd "OK, ${infile} was deleted."
        else
          http._wd "ERROR: unable to delete existing ${infile}. Check permissions."
        fi
       else
        http._wd "SKIP: ${infile} is not an export file."
      fi
    else
      http._wd "SKIP: ${infile} is not readable."
    fi
  }

  # ======================================================================
  # SETTER
  # ======================================================================

  # set authentication
  # param  string  USER:PASSWORD
  function http.setAuth(){
    http._wd "${FUNCNAME[0]}($1)"
    if [ -z "$1" ]; then
      http_req__auth=
    else
      http_req__auth="-u $1"
    fi
  }
  # set body to send for PUTs and POSTs
  # param  string  body
  function http.setBody(){
    http._wd "${FUNCNAME[0]}($1)"
    http_req__body=$1
  }
  # set a base url of an API
  # Remark: Then use http.setUrl to complet the url to request
  # param  string  url
  function http.setBaseUrl(){
    http._wd "${FUNCNAME[0]}($1)"
    http_req__baseurl=$1
    http.setFullUrl
  }
  # Enable or disable debug mode
  # param  integer  0|1
  function http.setDebug(){
    http._wd "${FUNCNAME[0]}($1)"
    http_cfg__debug=$1
  }
  function http.setDocs(){
    http._wd "${FUNCNAME[0]}($1)"
    http_req__docs=$1
  }

  # set the method to use; GET|POST|PUT|DELETE
  # param  string  name of method
  function http.setMethod(){
    http._wd "${FUNCNAME[0]}($1)"
    http_req__method=$1
  }

  # set a full url to request
  # param  string  url
  function http.setFullUrl(){
    http._wd "${FUNCNAME[0]}($1)"
    if [ -z "$1" ]; then
      http_req__fullurl=${http_req__baseurl}${http_req__url}
    else
      http_req__fullurl=$1
    fi
  }
  # complete the base url
  # param  string  url part behind base url
  function http.setUrl(){
    http._wd "${FUNCNAME[0]}($1)"
    http_req__url=$1
    http.setFullUrl
  }

  # ----- caching

  function http.setCacheTtl(){
    http._wd "${FUNCNAME[0]}($1)"
    http_cfg__cacheTtl=$1
  }

  function http.setCacheFile(){
    http._wd "${FUNCNAME[0]}($1)"
    http_cfg__cacheFile="$1"
  }

  function http.flushCache(){
    http._wd "${FUNCNAME[0]}($1)"
    rm -f ${http_cfg__cacheDir}/*
  }

  # ......................................................................
  #
  # show a help text
  # no params
  function http.help(){
    cat <<EOH

$http_cfg__about

This is a bash solution to script REST API calls.

Source:$http_cfg__prjurl
License: GNU GPL 3


INSTRUCTION:

- Source the file once
- Then you can run functions starting with "http."

    http.init
      Start a new request. It resets internal vars of the last response
      (if there was one).

    http.setDebug 0|1
      Enable or disable debugging infos during processing. It is written
      to STDERR.

- initialize a request

    setAuth AUTH:PASSWORD
      set authentication

    http.setBody DATA
      set a body for POST/ PUT requests.

    http.setBaseUrl URL
      Set a base url to an api.
      renmark:
      Use http.setUrl to built a complete url.

    http.setDocs URL

    http.setMethod METHOD
      Set a http method. Use an uppercase string for GET|POST|PUT|DELETE|...

    http.setFullUrl URL
      Set a complete url for a request.

    http.setUrl REQUEST?QUERY
      Set a relative url for a request.
      This requires to use http.setBaseUrl before.

- caching functions

    http.setCacheTtl SECONDS
      Enable caching with values > 0
      Remark: only GET requests will be cached.
      Default: 0 (no caching)

    http.setCacheFile FILENAME
      Set a file where to read/ store a request
      Default: empty; autogenerated file below $http_cfg__cacheDir

    http.flushCache
      Delete all files in $http_cfg__cacheDir

- make the request

    http.makeRequest [[METHOD] [URL] [BODY]]
      The parameters are optional. Without parameter the rquest will be
      started with given data in http.set* functions described above.
      If minimum one pram is given then they are handled:
        METHOD  optional: set a method (must be uppercase) - see http.setMethod
        URL     set a relative url - see http.setUrl
        BODY    optional: set a body - see http.setBody

      The request will be skipped and uses a cached content if ...
        - METHOD is GET
        - http.setCacheTtl set a value > 0
        - the cache file exists and is younger than the given TTL

- handle response

      http.getResponse
        Get the Response Body

      http.getResponseData
        Get Meta infos from curl

      http.getResponseHeader
        Get The http reponse header

- check http status code

      http.getStatuscode
        Get the http status code of a request

      http.isOk
        Check if the http response code is a 2xx

      http.isRedirect
        Check if the http response code is a 3xx

      http.isError
        Check if the http response code is a 4xx or 5xx

      http.isClientError
        Check if the http response code is a 4xx

      http.isServerError
        Check if the http response code is a 5xx

      http.getRequestAge
        Get the age of the request in seconds.
        Remark: This function is useful after an import
        see http.responseImport.

      http.getRequestTs
        Get the Unix timestamp of the request

- import/ export

      http.responseExport [FILE]
        dump the response data
        Without parameter it is written on STDOUT.
        You can set a filename to write it to a file.
        The filename can contain "AUTOFILE" this string
        will be replaced with a uniq string.
        (requires sha1sum and a set url)
        Example:
        http.makeRequest "https://example.com/api/"
        http.responseExport /tmp/something_AUTOFILE_.txt

      http.responseImport FILE
        Import an export file.
        To use the AUTOFILE mechanism from export set
        the url first.
        Example:
        http.setFullUrl "https://example.com/api/"
        http.responseImport /tmp/something_AUTOFILE_.txt

      http.responseDelete FILE
        Delete a file after http.responseExport.
        It is useful if you use the AUTOFILE mechanism.

EOH
  }

# ----------------------------------------------------------------------
#
# main
#
# ----------------------------------------------------------------------

  http.init

# ----------------------------------------------------------------------
