# frozen_string_literal: true

class Issue
  attr_reader :changes, :raw

  def initialize raw:, timezone_offset: '00:00'
    @raw = raw
    @timezone_offset = timezone_offset
    @changes = []

    if @raw['changelog'].nil?
      raise "No changelog found in issue #{@raw['key']}. This is likely because when we pulled the data" \
      ' from Jira, we didn\'t specify expand=changelog. Without that changelog, nothing else is going to' \
      ' work so stopping now.'
    end

    @raw['changelog']['histories'].each do |history|
      created = parse_datetime(history['created'])
      author = history['author']['displayName'] || history['author']['name']
      history['items'].each do |item|
        @changes << ChangeItem.new(raw: item, time: created, author: author)
      end
    end

    # It might appear that Jira already returns these in order but we've found different
    # versions of Server/Cloud return the changelog in different orders so we sort them.
    sort_changes!

    # Initial creation isn't considered a change so Jira doesn't create an entry for that
    @changes.insert 0, create_fake_change_for_creation(@changes)
  end

  def sort_changes!
    @changes.sort! do |a, b|
      # It's common that a resolved will happen at the same time as a status change.
      # Put them in a defined order so tests can be deterministic.
      compare = a.time <=> b.time
      compare = 1 if compare.zero? && a.resolution?
      compare
    end
  end

  def key = @raw['key']

  def type = @raw['fields']['issuetype']['name']

  def summary = @raw['fields']['summary']

  def status = @raw['fields']['status']['name']

  def status_id = @raw['fields']['status']['id'].to_i

  def labels = @raw['fields']['labels']

  def author = @raw['fields']['creator']['displayName']

  def resolution = @raw['fields']['resolution']['name']

  def url
    # Strangely, the URL isn't anywhere in the returned data so we have to fabricate it.
    "#{$1}/browse/#{key}" if @raw['self'] =~ /^(https?:\/\/[^\/]+)\//
  end

  def key_as_i
    $1.to_i if key =~ /\-(\d+)$/
  end

  def component_names
    @raw['fields']['components']&.collect { |component| component['name'] } || []
  end

  def create_fake_change_for_creation existing_changes
    created_time = parse_datetime @raw['fields']['created']
    first_change = existing_changes.find { |change| change.status? }
    if first_change.nil?
      # There have been no status changes yet so we have to look at the current status
      first_status = @raw['fields']['status']['name']
      first_status_id = @raw['fields']['status']['id'].to_i
    else
      # Otherwise, we look at what the first status had changed away from.
      first_status = first_change.old_value
      first_status_id = first_change.old_value_id
    end
    ChangeItem.new time: created_time, artificial: true, author: author, raw: {
      'field' => 'status',
      'to' => first_status_id.to_s,
      'toString' => first_status
    }
  end

  def first_time_in_status *status_names
    @changes.find { |change| change.matches_status status_names }&.time
  end

  def first_time_not_in_status *status_names
    @changes.find { |change| change.status? && status_names.include?(change.value) == false }&.time
  end

  def still_in
    time = nil
    @changes.each do |change|
      next unless change.status?

      current_status_matched = yield change

      if current_status_matched && time.nil?
        time = change.time
      elsif !current_status_matched && time
        time = nil
      end
    end
    time
  end
  private :still_in

  # If it ever entered one of these statuses and it's still there then what was the last time it entered
  def still_in_status *status_names
    still_in do |change|
      status_names.include?(change.value)
    end
  end

  # If it ever entered one of these categories and it's still there then what was the last time it entered
  def still_in_status_category config, *category_names
    still_in do |change|
      category = config.file_config.project_config.category_for status_name: change.value
      category_names.include? category
    end
  end

  def most_recent_status_change
    changes.reverse.find { |change| change.status? }
  end

  # Are we currently in this status? If yes, then return the time of the most recent status change.
  def currently_in_status *status_names
    change = most_recent_status_change
    return change.time if change.matches_status status_names
  end

  # Are we currently in this status category? If yes, then return the time of the most recent status change.
  def currently_in_status_category config, *category_names
    change = most_recent_status_change
    category = config.file_config.project_config.category_for status_name: change.value
    return change.time if category_names.include? category
  end

  def first_status_change_after_created
    @changes.find { |change| change.status? && change.artificial? == false }&.time
  end

  def first_time_in_status_category config, *category_names
    @changes.each do |change|
      next unless change.status?

      category = config.file_config.project_config.category_for status_name: change.value
      return change.time if category_names.include? category
    end
    nil
  end

  def parse_datetime text
    DateTime.parse(text).new_offset @timezone_offset
  end

  def created
    parse_datetime @raw['fields']['created']
  end

  def updated
    parse_datetime @raw['fields']['updated']
  end

  def first_resolution
    @changes.find { |change| change.resolution? }&.time
  end

  def last_resolution
    @changes.reverse.find { |change| change.resolution? }&.time
  end

  def assigned_to
    @raw['fields']&.[]('assignee')&.[]('displayName')
  end

  # TODO: Change to use new cycletime_config
  def blocked_percentage started, finished
    started = started.call self
    finished = finished.call self

    return '' if started.nil? || finished.nil?

    total_blocked_time = 0
    blocked_start = nil

    @changes.each do |change|
      next unless change.flagged?

      if change.value == 'Blocked'
        blocked_start = change.time
      else
        # It shouldn't be possible to get an unblock without first being blocked but we've
        # seen it in production so we have to handle it. Data integrity FTW.
        next if blocked_start.nil?

        if change.time >= started
          blocked_start = started if blocked_start < started
          blocked_end = change.time
          blocked_end = finished if blocked_end > finished
          total_blocked_time += (blocked_end.to_time - blocked_start.to_time)
        end
        blocked_start = nil
      end
    end

    total_time = (finished.to_time - started.to_time)
    total_blocked_time * 100.0 / total_time
  end

  # Many test failures are simply unreadable because the default inspect on this class goes
  # on for pages. Shorten it up.
  def inspect
    "Issue(#{key.inspect})"
  end

  def blocked_on_date? date
    blocked_start = nil
    changes.each do |change|
      next unless change.flagged?

      if change.value == '' # Flag is turning off
        # It's theoretically impossible for us to get a flag turning off *before* it gets
        # turned on and yet, we've seen this exact scenario in a production system so we
        # have to handle it.
        next if blocked_start.nil?

        range = blocked_start.to_date..change.time.to_date
        return true if range.include? date

        blocked_start = nil
      else
        # Flag is turning on. Note that Jira may pass in a variety of different values here
        # but all we care about is that it isn't an empty string.
        blocked_start = change.time
      end
    end

    if blocked_start
      date >= blocked_start
    else
      false
    end
  end

  def stalled_on_date? date, stalled_threshold = 5
    changes.each do |change|
      change_date = change.time.to_date
      next if change_date > date

      return false if (date - change_date).to_i < stalled_threshold
    end

    updated_date = updated.to_date
    return true if date < updated_date

    date >= updated_date && (date - updated_date).to_i >= stalled_threshold
  end
end
