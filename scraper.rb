#!/bin/env ruby
# encoding: utf-8

require 'rexml/document'
require 'pry'
require 'uri'
require 'scraped'
require 'scraperwiki'

include REXML

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

url = 'https://business.senedd.wales/mgwebservice.asmx/GetCouncillorsByWard'

class String
  def tidy
    self.gsub(/[[:space:]]+/, ' ').strip
  end

  def slugify
    self.downcase.gsub(' ', '_')
  end

  def to_date
    Date.parse(self).to_s rescue nil
  end
end

def parse_xml(doc)
  doc.get_elements('//ward').each do |ward|
    constituency = ward.get_text('wardtitle').to_s

    ward.get_elements('councillors/councillor').each do |member|
      if constituency.to_s.empty? || constituency.to_s.strip == 'No Ward'
        area = member.get_text('districttitle').to_s
        area_id = 'ocd-division/country:gb-wls/region:%s' % area.slugify
      else
        region = '-'
        area = constituency
        area_id = 'ocd-division/country:gb-wls/region:%s/constituency:%s' % [region.slugify, constituency.slugify]
      end

      data = {
        id: member.get_text('councillorid').to_s,
        name: member.get_text('fullusername').to_s,
        party: member.get_text('politicalpartytitle').to_s,
        area_id: area_id,
        area: area,
        email: member.get_text('workaddress/email').to_s,
        image: member.get_text('photobigurl').to_s,
        term: 6
      }

      if data[:name].to_s.empty?
        warn 'No data for found rep'
        return
      end

      if matched = data[:name].match(/(.*) \((.*)\)/)
        data[:name] = matched.captures[0]
        data[:other_name] = matched.captures[1]
      end

      #     # Dates of most recent term
      #     if (term_dates = noko.xpath('.//h2[contains(.,"Term")]/following-sibling::ul[1]/li')).any?
      #       last_term = term_dates.last.text.split(' - ').map { |s| s.to_s.to_date }
      #       data[:start_date], data[:end_date] = last_term if last_term.first > '2016-05-01'
      #     end

      ScraperWiki.save_sqlite([:id, :term, :party], data)
    end
  end
end

ScraperWiki.sqliteexecute('DROP TABLE data') rescue nil
doc = Document.new open(url)
parse_xml doc
