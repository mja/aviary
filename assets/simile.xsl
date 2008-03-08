<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method='xml' version='1.0' encoding='UTF-8' indent='yes'/>

<xsl:template match="/">
  <data>
    <xsl:for-each select="statuses/status">
    <xsl:sort select="created_at"/>  
      <event>
        <xsl:attribute name="start">
         <xsl:value-of select="created_at"/>
        </xsl:attribute>
        <xsl:attribute name="title">
          <xsl:value-of select="id"/>
        </xsl:attribute>
        <xsl:value-of select="text"/>
      </event>
    </xsl:for-each>
  </data>
</xsl:template>
</xsl:stylesheet>