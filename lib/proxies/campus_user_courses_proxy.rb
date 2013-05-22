class CampusUserCoursesProxy < BaseProxy
  extend Proxies::EnableForActAs

  APP_ID = "Campus"

  def initialize(options = {})
    super(Settings.sakai_proxy, options)
    @uid = @settings.fake_user_id if @fake
  end

  def self.access_granted?(uid)
    !uid.blank?
  end

  def current_terms
    @settings.current_terms_codes
  end

  # Example:
  # {
  #    "id": "COG SCI:C102:2013-B",
  #    "course_code": "COG SCI C102",
  #    "ccn": "23731"
  #    "site_url": "/academics/semester/spring-2013/class/12345",
  #    "emitter": "Campus",
  #    "name": "Scientific Approaches to Consciousness",
  #    "color_class": "campus-class",
  #    "courses": [{
  #      "term_yr": "2013",
  #      "term_cd": "B",
  #      "dept": "COG SCI",
  #      "catid": "C102"
  #    }]
  #    "role": "Student", (or "Instructor")
  #    "waitlist_pos": 2
  # },
  def get_campus_courses
    self.class.fetch_from_cache @uid do
      campus_classes = []
      previous_id = nil
      current_terms.each do |term|
        term_yr = term.term_yr
        term_cd = term.term_cd
        # The SQL ordering is such that the feed currently only needs the first section record for every
        # course offering. If we later have a need for the full list of sections, they're available.
        enrollments = CampusData.get_enrolled_sections(@uid, term_yr, term_cd)
        enrollments.each do |row|
          if (item = row_to_feed_item(row, previous_id))
            item[:role] = 'Student'
            item[:unit] = row['unit']
            item[:pnp_flag] = row['pnp_flag']
            if row['enroll_status'] == 'W'
              item[:waitlist_pos] = row['wait_list_seq_num']
            end
            campus_classes << item
            previous_id = item[:id]
          end
        end
        assigneds = CampusData.get_instructing_sections(@uid, term_yr, term_cd)
        assigneds.each do |row|
          if (item = row_to_feed_item(row, previous_id))
            item[:role] = 'Instructor'
            campus_classes << item
            previous_id = item[:id]
          end
        end
      end
      campus_classes.each do |course|
        add_schedule_to_feed!(course)
        add_instructor_to_feed!(course)
      end
      campus_classes
    end
  end

  def row_to_feed_item(row, previous_id)
    Rails.logger.info "Row = #{row}"
    course_id = "#{row['dept_name']}:#{row['catalog_id']}:#{row['term_yr']}-#{row['term_cd']}"
    if course_id == previous_id
      nil
    else
      {
          id: course_id,
          course_code: "#{row['dept_name']} #{row['catalog_id']}",
          ccn: row['course_cntl_num'],
          site_url: course_to_url(row['term_cd'], row['term_yr'], row['dept_name'], row['course_cntl_num']),
          emitter: 'Campus',
          name: row['course_title'],
          color_class: "campus-class",
          instruction_format:  row['instruction_format'],
          section_num:  row['section_num'],
          courses: [{
              term_yr: row['term_yr'],
              term_cd: row['term_cd'],
              dept: row['dept_name'],
              catid: row['catalog_id'],
              ccn: row['course_cntl_num']
          }]
      }
    end
  end

  def add_schedule_to_feed!(course)
    schedule = CampusData.get_class_schedule(
      course[:courses][0][:term_yr],
      course[:courses][0][:term_cd],
      course[:courses][0][:ccn])
    if schedule
      # TODO add building map data if available
      course.merge!({:building_name => schedule['building_name'],
                     :room_number => schedule['room_number'],
                     :schedule => translate_meeting(schedule)
                    })
    end
  end

  def add_instructor_to_feed!(course)
    instructor = CampusData.get_instructor(
      course[:courses][0][:term_yr],
      course[:courses][0][:term_cd],
      course[:courses][0][:ccn])
    if instructor
      course.merge!({:instructor => instructor['person_name']})
    end
  end

  # Link campus courses to internal class pages for the current semester.
  # TODO: Update to use full class IDs, not just CCNs
  def course_to_url(term_cd, term_year, department, ccn)
    term = case term_cd
             when 'B' then 'spring'
             when 'C' then 'summer'
             when 'D' then "fall"
             else
               Rails.logger.warn("Unknown term code #{term_cd} for #{department} #{ccn}")
               return ''
           end
    "/academics/semester/#{term}-#{term_year}/class/#{ccn}"
  end

  def translate_meeting(schedule)
    if schedule.nil?
      return ""
    end
    days = schedule['meeting_days'] || nil
    if days.nil?
      return ""
    end
    schedule_string = ""
    if days.length > 0 && !days[0].blank?
      schedule_string += "Su"
    end
    if days.length > 1 && !days[1].blank?
      schedule_string += "M"
    end
    if days.length > 2 && !days[2].blank?
      schedule_string += "Tu"
    end
    if days.length > 3 && !days[3].blank?
      schedule_string += "W"
    end
    if days.length > 4 && !days[4].blank?
      schedule_string += "Th"
    end
    if days.length > 5 && !days[5].blank?
      schedule_string += "F"
    end
    if days.length > 6 && !days[6].blank?
      schedule_string += "Sa"
    end

    unless schedule['meeting_start_time'].nil?
      schedule_string += " #{to_time(schedule['meeting_start_time'])}#{schedule['meeting_start_time_ampm_flag']}"
    end

    unless schedule['meeting_end_time'].nil?
      schedule_string += "-#{to_time(schedule['meeting_end_time'])}#{schedule['meeting_end_time_ampm_flag']}"
    end

    schedule_string
  end

  def to_time(str)
    num = str.gsub(/^0/, "")
    formatted = num.insert(num.length - 2, ":")
    formatted
  end

end
