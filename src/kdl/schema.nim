# TODO: implement the KDL schema language specification https://github.com/kdl-org/kdl/blob/main/SCHEMA-SPEC.md

import std/options
import nodes, types

type
  Document* = object
    info*: Info
    node*: seq[Node] # Zero or more
    defs*: Option[Defs]
    nodeNames*: Option[Validations]
    otherNodesAllowed*: bool
    tag*: seq[Tag]
    tagNames*: Option[Validations]
    otherTagsAllowed*: bool

  Info* = object
    title*: seq[Title] # Zero or more
    desc*: seq[Description] # Zero or more
    author*: seq[Author] # Zero or more
    contributor*: seq[Author] # Zero or more
    link*: seq[Link] # Zero or more
    license*: seq[License] # Zero or more
    published*: Option[Published]
    modified*: Option[Published]
    version*: Option[Version]

  Title* = object
    title*: string
    lang*: Option[string] # An IETF BCP 47 language tag

  Description* = object
    desc*: string
    lang*: Option[string] # An IETF BCP 47 language tag

  Author* = object
    name*: string
    orcid*: Option[string]
    links*: seq[Link] # Zero or more

  Link* = object
    uri*: string # URI/IRI
    rel*: string # "self" or "documentation"
    lang*: Option[string] # An IETF BCP 47 language tag

  License* = object
    name*: string
    spdx*: Option[string] # An SPDX license identifier
    links*: seq[Link] # One or more

  Published* = object
    date*: string # As a ISO8601 date
    time*: Option[string] # An ISO8601 Time to accompany the date


  Version* = string # SemVer https://github.com/euantorano/semver.nim

  Node* = object
    name*: Option[string]
    desc*: Option[string]
    id*: Option[string] # Unique
    refQuery*: Option[string] # KDL Query

    min*, max*: Option[int]
    propNames*: Option[Validations]
    otherPropsAllowed*: bool
    tag*: Validations
    prop*: seq[Prop] # Zero or more
    value*: seq[Value] # Zero or more
    children*: seq[Children] # Zero or more

  Tag* = object
    name*: Option[string]
    desc*: Option[string]
    id*: Option[string] # Unique
    refQuery*: Option[string] # KDL Query

    node*: seq[Node] # Zero or more
    nodeNames*: Option[Validations]
    otherNodesAllowed*: bool

  Prop* = object
    key*: Option[string]
    desc*: Option[string]
    id*: Option[string] # Unique
    refQuery*: Option[string] # KDL Query

    required*: Option[bool]
    # Any validation node    

  Value* = object
    desc*: Option[string]
    id*: Option[string] # Unique
    refQuery*: Option[string] # KDL Query

    min*, max*: Option[int]

    # Any validation node    

  Children* = object
    desc*: Option[string]
    id*: Option[string] # Unique
    refQuery*: Option[string] # KDL Query

    node*: seq[Node] # Zero or more
    nodeNames*: Option[Validations]
    otherNodesAllowed*: bool

  Format = enum
    DateTime # ISO8601 date/time format
    Time # Time section of ISO8601
    Date # Date section of ISO8601
    Duration # ISO8601 duration format
    Decimal # IEEE 754-2008 decimal string format
    Currency # ISO 4217 currency code
    Country2 # ISO 3166-1 alpha-2 country code
    Country3 # ISO 3166-1 alpha-3 country code
    CountrySubdivision # ISO 3166-2 country subdivison code
    Email # RFC5302 email address
    IdnEmail # RFC6531 internationalized email adress
    HostName # RFC1132 internet hostname
    IdnHostName # RFC5890 internationalized internet hostname
    Ipv4 # RFC2673 dotted-quad IPv4 address
    Ipv6 # RFC2373 IPv6 address
    Url # RFC3986 URI
    UrlReference # RFC3986 URI Reference
    Irl # RFC3987 Internationalized Resource Identifier
    IrlReference # RFC3987 Internationalized Resource Identifier Reference
    UrlTemplate # RFC6570 URI Template
    Uuid # RFC4122 UUID
    Regex # Regular expression. Specific patterns may be implementation-dependent
    Base64 # A Base64-encoded string, denoting arbitrary binary data
    KdlQuery # A KDL Query string

  Validations* = ref object
    tag*: Validations
    `enum`*: seq[KdlVal] # List of allowed values for this property
    case kind*: KValKind # Type of the property value
    of KString:
      pattern*: string # Regex
      minLength*, maxLength*: int
      format*: Format
    of KFloat, KInt:
      `%`*: string

    else: discard

  Defs* = object
    node*: seq[Node] # Zero or more
    tag*: seq[Tag] # Zero or more
    prop*: seq[Prop] # Zero or more
    value*: seq[Value] # Zero or more
    children*: seq[Children] # Zero or more

