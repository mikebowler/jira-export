require './spec/spec_helper'

def load_issue key
  Issue.new(JSON.parse(File.read("spec/#{key}.json")))
end

describe Issue do
  it "gets key" do
    issue = load_issue 'SP-2'
    expect(issue.key).to eql 'SP-2'
  end

  it "gets simple history with a single status" do
    issue = load_issue 'SP-2'

    changes = [
      ChangeItem.new(field: "status", value: "Backlog", time: '2021-06-18T18:41:37.804+0000'),
      ChangeItem.new(field: "status", value: "Selected for Development", time: '2021-06-18T18:43:38+00:00')
    ]

    expect(issue.changes).to eq changes
  end

  it "gets complex history with a mix of field types" do 
    issue = load_issue 'SP-10'
    changes = [
      ChangeItem.new(field: "status",     value: "Backlog",                  time: '2021-06-18T18:42:52.754+0000'),
      ChangeItem.new(field: "status",     value: "Selected for Development", time: '2021-08-29T18:06:28+00:00'),
      ChangeItem.new(field: "Rank",       value: "Ranked higher",            time: '2021-08-29T18:06:28+00:00'),
      ChangeItem.new(field: "priority",   value: "Highest",                  time: '2021-08-29T18:06:43+00:00'),
      ChangeItem.new(field: "status",     value: "In Progress",              time: '2021-08-29T18:06:55+00:00'),
      ChangeItem.new(field: "status",     value: "Selected for Development", time: '2021-09-06T04:33:11+00:00'),
      ChangeItem.new(field: "Flagged",    value: "Impediment",               time: '2021-09-06T04:33:30+00:00'),
      ChangeItem.new(field: "priority",   value: "Medium",                   time: '2021-09-06T04:33:50+00:00'),
      ChangeItem.new(field: "Flagged",    value: "",                         time: '2021-09-06T04:33:55+00:00'),
      ChangeItem.new(field: "status",     value: "In Progress",              time: '2021-09-06T04:34:02+00:00'),
      ChangeItem.new(field: "status",     value: "Review",                   time: '2021-09-06T04:34:21+00:00'),
      ChangeItem.new(field: "status",     value: "Done",                     time: '2021-09-06T04:34:26+00:00'),
      ChangeItem.new(field: "resolution", value: "Done",                     time: '2021-09-06T04:34:26+00:00')
     ]
    expect(issue.changes).to eq changes
  end

  it "first time in status" do
    issue = load_issue 'SP-10'
    expect(issue.first_time_in_status('In Progress').to_s).to eql '2021-08-29T18:06:55+00:00'
  end

  it "first time in status that doesn't match any" do
    issue = load_issue 'SP-10'
    expect(issue.first_time_in_status('NoStatus')).to be_nil
  end

  it "first time not in status" do
    issue = load_issue 'SP-10'
    expect(issue.first_time_not_in_status('Backlog').to_s).to eql '2021-08-29T18:06:28+00:00'
  end

  it "first time not in status that doesn't match any" do
    issue = load_issue 'SP-10'
    expect(issue.first_time_in_status('NoStatus')).to be_nil
  end

  it "first time for any status change - created doesn't count as status change" do 
    issue = load_issue 'SP-10'
    expect(issue.first_status_change_after_created.to_s).to eql '2021-08-29T18:06:28+00:00'
  end

  context "still_in_status" do 
    it "item moved to done and then back to in progress" do
      issue = load_issue 'SP-10'
      issue.changes << ChangeItem.new(field: "status", value: "In Progress", time: '2021-10-01T00:00:00+00:00')
      expect(issue.still_in_status('Done')).to be_nil
    end

    it "item moved to done, back to in progress, then to done again" do
      issue = load_issue 'SP-10'
      issue.changes << ChangeItem.new(field: "status", value: "In Progress", time: '2021-10-01T00:00:00+00:00')
      issue.changes << ChangeItem.new(field: "status", value: "Done", time: '2021-10-02T00:00:00+00:00')
      expect(issue.still_in_status('Done').to_s).to eql '2021-10-02T00:00:00+00:00'
    end

    it "item moved to done twice should return first time only" do
      issue = load_issue 'SP-10'
      issue.changes << ChangeItem.new(field: "status", value: "In Progress", time: '2021-10-01T00:00:00+00:00')
      issue.changes << ChangeItem.new(field: "status", value: "Done", time: '2021-10-02T00:00:00+00:00')
      issue.changes << ChangeItem.new(field: "status", value: "Done", time: '2021-10-03T00:00:00+00:00')
      expect(issue.still_in_status('Done').to_s).to eql '2021-10-02T00:00:00+00:00'
    end

    it "doesn't match any" do
      issue = load_issue 'SP-10'
      expect(issue.still_in_status('NoStatus')).to be_nil
    end
  end

  context "still_in_status_category" do
    def mock_config
      config = ConfigBase.new file_prefix: nil, jql: ''
      config.status_category_mappings['Story'] = {
        'Backlog' => 'ready',
        'Selected for Development' => 'ready',
        "In Progress" => 'in-flight',
        'Review' => 'in-flight',
        'Done' => 'finished'
      }
      config
    end

    it "item moved to done and then back to in progress" do
      issue = load_issue 'SP-10'
      issue.changes << ChangeItem.new(field: "status", value: "In Progress", time: '2021-10-01T00:00:00+00:00')
      expect(issue.still_in_status_category(mock_config, 'finished')).to be_nil
    end

    it "item moved to done, back to in progress, then to done again" do
      issue = load_issue 'SP-10'
      issue.changes << ChangeItem.new(field: "status", value: "In Progress", time: '2021-10-01T00:00:00+00:00')
      issue.changes << ChangeItem.new(field: "status", value: "Done", time: '2021-10-02T00:00:00+00:00')
      expect(issue.still_in_status_category(mock_config, 'finished').to_s).to eql '2021-10-02T00:00:00+00:00'
    end

    it "item moved to done twice should return first time only" do
      issue = load_issue 'SP-10'
      issue.changes << ChangeItem.new(field: "status", value: "In Progress", time: '2021-10-01T00:00:00+00:00')
      issue.changes << ChangeItem.new(field: "status", value: "Done", time: '2021-10-02T00:00:00+00:00')
      issue.changes << ChangeItem.new(field: "status", value: "Done", time: '2021-10-03T00:00:00+00:00')
      expect(issue.still_in_status_category(mock_config, 'finished').to_s).to eql '2021-10-02T00:00:00+00:00'
    end
  end
end