#!/bin/env ruby
# encoding: utf-8

require 'csv'
require 'pry'
require 'scraped'
require 'scraperwiki'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

@ConstituencyRegion = {}
url = "https://senedd.wales/Umbraco/Api/Committee/DownloadCommitteeMembersCsv?committeeId=355743&cultureInfo=en-GB"

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

def parse_csv(csv_data)
  csv_data.each do |member|
    constituency = member[:constituency]
    if constituency.to_s.empty? || constituency.to_s.strip == "-"
      area = member[:region]
      area_id = 'ocd-division/country:gb-wls/region:%s' % area.slugify
    else
      region = member[:region]
      area = constituency
      area_id = 'ocd-division/country:gb-wls/region:%s/constituency:%s' % [region.slugify, constituency.slugify]
    end

    data = {
      name: member[:name],
      party: member[:party],
      area_id: area_id,
      area: area,
      email: member[:email_address],
      term: 6
    }

    if data[:name].to_s.empty?
      warn "No data for found rep"
      return
    end

    data[:image] = URI.join(url, data[:image]).to_s unless data[:image].to_s.empty?
    if matched = data[:name].match(/(.*) \((.*)\)/)
      data[:name] = matched.captures[0]
      data[:other_name] = matched.captures[1]
    end

    #     # Dates of most recent term
    #     if (term_dates = noko.xpath('.//h2[contains(.,"Term")]/following-sibling::ul[1]/li')).any?
    #       last_term = term_dates.last.text.split(' - ').map { |s| s.to_s.to_date }
    #       data[:start_date], data[:end_date] = last_term if last_term.first > '2016-05-01'
    #     end

    ScraperWiki.save_sqlite([:email, :term, :party], data)
  end
end

ScraperWiki.sqliteexecute('DROP TABLE data') rescue nil
csv_data = CSV.readlines(open(url), headers: true, encoding: 'iso-8859-1:utf-8', header_converters: :symbol)
parse_csv csv_data
