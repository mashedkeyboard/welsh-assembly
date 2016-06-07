#!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'nokogiri'
require 'colorize'
require 'pry'
require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

@ConstituencyRegion = {}

class String
  def tidy
    self.gsub(/[[:space:]]+/, ' ').strip
  end

  def slugify
    self.downcase.gsub(' ','_')
  end

  def to_date
    Date.parse(self).to_s rescue nil
  end
end

def noko_for(url)
  Nokogiri::HTML(open(url).read)
end


def scrape_region(url)
  noko = noko_for(url)
  region = noko.css('h1').text.split(':').last.tidy
  noko.css('div#genericListing h2 a/@href').each do |href|
    scrape_person(URI.join(url, href.text), region)
  end
end

def scrape_person(url, region=nil)
  noko = noko_for(url)
  sidebar = noko.css('div.mgUserSideBar')
  userbody = noko.css('div.mgUserBody')

  constituency = sidebar.xpath('.//span[contains(.,"Constituency:")]/following-sibling::text()').text.tidy
  if constituency.to_s.empty?
    area = sidebar.xpath('.//span[contains(.,"Region:")]/following-sibling::text()').text.tidy
    area = 'North Wales' if url.to_s.include? 'UID=407' # No longer on page
    area_id = 'ocd-division/country:gb-wls/region:%s' % area.slugify 
  else
    # Constituency Member Pages don't have the Region that constituency is in
    # So if we got here from a Region page, cache what Region that was
    # Otherwise (e.g. for historic AMs), fetch the region from that cache
    if region
      @ConstituencyRegion[constituency] = region
    else 
      region = @ConstituencyRegion[constituency]
    end
    area = constituency
    area_id = 'ocd-division/country:gb-wls/region:%s/constituency:%s' % [region.slugify, constituency.slugify]
  end
  
  data = { 
    id: url.to_s[/mid=(\d+)/, 1],
    name: noko.css('div.text h1').text.tidy.sub(/ AM$/,''),
    role: sidebar.xpath('.//span[contains(.,"Title:")]/following-sibling::text()').text.tidy,
    party: sidebar.xpath('.//span[contains(.,"Party:")]/following-sibling::text()').text.tidy,
    area_id: area_id,
    area: area,
    image: noko.css('.mgBigPhoto img/@src').text.tidy,
    email: userbody.css('a[title*=email]').text.tidy,
    website: userbody.css('a[title*=Website]/@href').text.tidy,
    facebook: userbody.css('a[title*=Facebook]/@href').text.tidy,
    twitter: userbody.css('a[title*=Twitter]/@href').text.tidy,
    term: 5,
    source: url.to_s,
  }
  data[:image] = URI.join(url, data[:image]).to_s unless data[:image].to_s.empty?
  if matched = data[:name].match(/(.*) \((.*)\)/)
    data[:name] = matched.captures[0]
    data[:other_name] = matched.captures[1]
  end

  # Dates of most recent term
  if (term_dates = noko.xpath('.//h2[contains(.,"Term")]/following-sibling::ul[1]/li')).any?
    last_term = term_dates.last.text.split(' - ').map { |s| s.to_s.to_date } 
    data[:start_date], data[:end_date] = last_term if last_term.first > '2016-05-01'
  end

  ScraperWiki.save_sqlite([:id, :term, :party], data)
end

(1..5).each do |region_id|
  scrape_region 'http://www.assembly.wales/en/memhome/Pages/membersearchresults.aspx?region=%s' % region_id
end


