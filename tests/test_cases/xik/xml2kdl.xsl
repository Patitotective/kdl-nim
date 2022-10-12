<?xml version="1.0" encoding="UTF-8" ?>
<xsl:transform xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
               version="1.0">
    <xsl:output method="text" encoding="UTF-8"/>

    <xsl:strip-space elements="*"/>

    <!--
        This XSL Transform is intended to convert any XML 1.0 document to a KDL file.
        The full KDL specification can be found at https://kdl.dev/
        The spec for XML-in-KDL can be found at https://github.com/kdl-org/kdl/blob/main/XML-IN-KDL.md
    -->

    <!-- HELPER FUNCTIONS -->
    <xsl:template name="replace-string">
        <!-- A find/replace function as we do not know if the XSLT processor will
             support XSLT 2 -->
        <xsl:param name="text"/>
        <xsl:param name="replace"/>
        <xsl:param name="with"/>
        <xsl:choose>
            <xsl:when test="contains($text,$replace)">
                <xsl:value-of select="substring-before($text,$replace)"/>
                <xsl:value-of select="$with"/>
                <xsl:call-template name="replace-string">
                    <xsl:with-param name="text" select="substring-after($text,$replace)"/>
                    <xsl:with-param name="replace" select="$replace"/>
                    <xsl:with-param name="with" select="$with"/>
                </xsl:call-template>
            </xsl:when>
            <xsl:otherwise>
                <xsl:value-of select="$text"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <xsl:template name="KDLCharEscape">
        <xsl:param name="val"/>
        <!-- Just a big ol' recursive function to escape special chars in strings. -->
        <xsl:call-template name="replace-string">
            <xsl:with-param name="text">
                <xsl:call-template name="replace-string">
                    <xsl:with-param name="text">
                        <xsl:call-template name="replace-string">
                            <xsl:with-param name="text">
                                <xsl:call-template name="replace-string">
                                    <xsl:with-param name="text">
                                        <xsl:call-template name="replace-string">
                                            <xsl:with-param name="text">
                                                <xsl:call-template name="replace-string">
                                                    <xsl:with-param name="text" select="$val"/>
                                                    <!-- Double quote character -->
                                                    <xsl:with-param name="replace"><xsl:text>\</xsl:text></xsl:with-param>
                                                    <xsl:with-param name="with"><xsl:text>\\</xsl:text></xsl:with-param>
                                                </xsl:call-template>
                                            </xsl:with-param>
                                            <!-- Double forward slash character -->
                                            <xsl:with-param name="replace"><xsl:text>/</xsl:text></xsl:with-param>
                                            <xsl:with-param name="with"><xsl:text>\/</xsl:text></xsl:with-param>
                                        </xsl:call-template>
                                    </xsl:with-param>
                                    <!-- Double quote character -->
                                    <xsl:with-param name="replace"><xsl:text>&quot;</xsl:text></xsl:with-param>
                                    <xsl:with-param name="with"><xsl:text>\&quot;</xsl:text></xsl:with-param>
                                </xsl:call-template>
                            </xsl:with-param>
                            <!-- Tab character -->
                            <xsl:with-param name="replace"><xsl:text>&#x9;</xsl:text></xsl:with-param>
                            <xsl:with-param name="with"><xsl:text>\t</xsl:text></xsl:with-param>
                        </xsl:call-template>
                    </xsl:with-param>
                    <!-- Carraige Return -->
                    <xsl:with-param name="replace"><xsl:text>&#13;</xsl:text></xsl:with-param>
                    <xsl:with-param name="with"><xsl:text>\r</xsl:text></xsl:with-param>
                </xsl:call-template>
            </xsl:with-param>
            <!-- Line Feed -->
            <xsl:with-param name="replace"><xsl:text>&#10;</xsl:text></xsl:with-param>
            <xsl:with-param name="with"><xsl:text>\n</xsl:text></xsl:with-param>
        </xsl:call-template>
    </xsl:template>

    <xsl:template name="indent">
        <!-- Rough attempt at indenting the output file. -->
        <xsl:param name="indents" select="0"/>
        <!-- Why &#32; instead of just a space? MSXML6 strips spaces from all text fields that are space only. -->
        <xsl:if test="$indents &gt; 0">
            <xsl:text>&#32;&#32;&#32;&#32;</xsl:text>
            <xsl:call-template name="indent">
                <xsl:with-param name="indents" select="$indents -1 "/>
            </xsl:call-template>
        </xsl:if>
    </xsl:template>


    <!-- HELPER FUNCTIONS END HERE -->
    <!-- ACTUAL TRANSFORM START HERE -->

    <xsl:template match="comment()">
        <xsl:param name="indents" select="0"/>
        <xsl:call-template name="indent">
            <xsl:with-param name="indents" select="$indents"/>
        </xsl:call-template>

        <!-- KDL comments take the format
            // single line comment
            or
            /*  multi
                line
                comment */
            We just use multi-line for everything -->
        <xsl:text>/* </xsl:text>
        <xsl:value-of select="normalize-space(.)"/>
        <xsl:text> */</xsl:text>
        <xsl:text>&#xa;</xsl:text>
    </xsl:template>

    <xsl:template match="processing-instruction()">
        <!--
            The contents of a PI are technically completely unstructured.
            However, in practice most PIs' contents look like start-tag attributes.
            If this is the case, they should be encoded as properties on the node, with string values.
            If the contents of a PI do not look like attributes, then instead the entire contents
            (from the end of the whitespace following the PI name, to the closing ?> characters)
            are encoded as a single unnamed string value.
            I need to put more intelligent logic in here to determine this, but for now we put raw string.
        -->
        <xsl:text>?</xsl:text>
        <xsl:value-of select="name()"/>
        <xsl:text> r#"</xsl:text>
        <xsl:value-of select="normalize-space(.)"/>
        <xsl:text>"#;</xsl:text>
        <xsl:text>&#xa;</xsl:text>
    </xsl:template>

    <xsl:template match="@*">
        <xsl:text>&#32;</xsl:text>
        <xsl:value-of select="name()"/>
        <xsl:text>=</xsl:text>
        <xsl:text>"</xsl:text>
        <xsl:call-template name="KDLCharEscape">
            <xsl:with-param name="val" select="."/>
        </xsl:call-template>
        <xsl:text>"</xsl:text>
    </xsl:template>

    <xsl:template match="*">
        <xsl:param name="indents" select="0"/>
        <xsl:call-template name="indent">
            <xsl:with-param name="indents" select="$indents"/>
        </xsl:call-template>
        <xsl:value-of select = "name(.)"/>
        <xsl:choose>
            <!-- We'll try and keep formatting of XHTML <pre> tags... no promises though! -->
            <xsl:when test="name(.)='pre' and namespace-uri()='http://www.w3.org/1999/xhtml' and count(*) = 0 ">
                <xsl:text>&#32;</xsl:text>
                <xsl:text>r#"</xsl:text>
                <xsl:value-of select="name(.)"/>
                <xsl:value-of select="."/>
                <xsl:text>"#</xsl:text>
            </xsl:when>
            <xsl:when test="count(*) = 0 and string-length(normalize-space(.)) &gt; 0">
                <xsl:text>&#32;</xsl:text>
                <xsl:text>&quot;</xsl:text>
                <xsl:call-template name="KDLCharEscape">
                    <xsl:with-param name="val" select="normalize-space(.)"/>
                </xsl:call-template>
                <!--
                    We want to strip excess whitespace, but it is probably still useful to include a single trailing
                    whitespace, for mixed content.
                 -->
                <xsl:if test="substring(., string-length(.) - string-length('&#32;') +1) = '&#32;'">
                    <xsl:text>&#32;</xsl:text>
                </xsl:if>
                <xsl:text>&quot;</xsl:text>
            </xsl:when>
        </xsl:choose>
        <xsl:apply-templates select="@*"/>
        <xsl:choose>
            <!-- End line if no child nodes -->
            <xsl:when test="not(count(*) &gt; 0)">
                <xsl:text>;</xsl:text>
                <xsl:text>&#xa;</xsl:text>
            </xsl:when>
            <!-- Mixed Content, split into list and reapply templates. -->
            <!-- If the element contains mixed text and element children,
                 the text can be encoded as a KDL node with the name - with a single string unnamed argument.
                 For example, the XML <span>some <b>bold</b> text</span>
                 can be encoded as span { - "some "; b "bold"; - " text" }.
                 -->
            <xsl:when test="count(*) &gt; 0 and count(text()) &gt; 0">
                <xsl:text> {</xsl:text>
                <xsl:text>&#xa;</xsl:text>
                <xsl:for-each select="node()">
                    <xsl:choose>
                        <!-- Prefixes the text nodes, applys templates for everything else -->
                        <xsl:when test="self::text()">
                            <xsl:call-template name="indent">
                                <xsl:with-param name="indents" select="$indents +1"/>
                            </xsl:call-template>
                            <xsl:text> - "</xsl:text>
                            <xsl:call-template name="KDLCharEscape">
                                <xsl:with-param name="val" select="normalize-space(.)"/>
                            </xsl:call-template>
                            <xsl:text>";</xsl:text>
                            <xsl:text>&#xa;</xsl:text>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:apply-templates select=".">
                                <xsl:with-param name="indents" select="$indents + 1"/>
                            </xsl:apply-templates>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:for-each>
                <xsl:call-template name="indent">
                    <xsl:with-param name="indents" select="$indents"/>
                </xsl:call-template>
                <xsl:text>};</xsl:text>
                <xsl:text>&#xa;</xsl:text>
            </xsl:when>
            <!-- Brackets and reapply templates if there are children -->
            <xsl:when test="count(*) &gt; 0">
                <xsl:text> {</xsl:text>
                <xsl:text>&#xa;</xsl:text>
                <xsl:apply-templates>
                    <xsl:with-param name="indents" select="$indents + 1"/>
                </xsl:apply-templates>
                <!-- Indent closing brackets -->
                <xsl:call-template name="indent">
                    <xsl:with-param name="indents" select="$indents"/>
                </xsl:call-template>
                <xsl:text>}</xsl:text>
                <xsl:text>&#xa;</xsl:text>
            </xsl:when>
        </xsl:choose>
    </xsl:template>

</xsl:transform>