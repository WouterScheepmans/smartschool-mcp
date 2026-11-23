# Courses

[Back to the overview](../../README.md)

Your courses ("vakken") as their teacher: the documents of a course, its
upload zones, where pupils hand in their work, and its news. For everyone,
without a switch. Tools that change something follow the
[shared rules](../../README.md#changes-and-approval).

| Tool | What it does | Changes Smartschool? |
| --- | --- | --- |
| [`list_courses`](#list_courses) | Lists your courses, with their ids | No |
| [`list_course_documents`](#list_course_documents) | Lists the folders and files of a course's documents | No |
| [`create_course_folder`](#create_course_folder) | Makes a folder in a course's documents | Yes, asks approval |
| [`upload_course_documents`](#upload_course_documents) | Uploads files from this PC to a course's documents | Yes, asks approval |
| [`list_upload_zones`](#list_upload_zones) | Lists the upload zones of a course | No |
| [`create_upload_zone`](#create_upload_zone) | Makes an upload zone in a course | Yes, asks approval |
| [`list_course_news`](#list_course_news) | Lists the news of a course, with the messages | No |
| [`post_course_news`](#post_course_news) | Posts a news item in a course | Yes, asks approval |

## Tools

### `list_courses`

Lists the courses of the course menu in Smartschool's top bar: your own
courses, those of the classes you are the titular of, and those of the
school community, each with its id and description (often its classes). The
other tools take a course by that id, or by its name when no other course
has it: several courses often share a name, one per group of classes.

### `list_course_documents`

Lists the folders and files at the top of a course's documents, or in one
folder, each with its id and whether pupils see it (and from and until
when, if set).

### `create_course_folder`

Makes a folder in a course's documents, at the top or in a folder, with an
optional description. Pupils see it unless `visible` is false, and only
from `visible_from` and until `visible_until` when those are given. Asks for
approval; Claude shows you the course, the place, the name and when pupils
see it first.

### `upload_course_documents`

Uploads 1 to 10 files from this PC to a course's documents, at the top or
in a folder, each under its own name, with the same visibility settings,
and optionally a notification to the pupils (`notify`, as "Opslaan en
melden"). Asks for approval; Claude shows you every file with its size, the
course and folder, and the settings first.

### `list_upload_zones`

Lists the upload zones of a course, each with its id and the folders of the
module it is in. What pupils uploaded is not read.

### `create_upload_zone`

Makes an upload zone at the top of a course's Uploadzone, with a name and an
optional description for the pupils. By default pupils can upload at any
time, see and open only their own files, and see the zone; `open_from` and
`open_until` (both or neither) limit when they can upload, `max_files` how
many files a pupil uploads, `classmates_see` and `classmates_read` let them
see and open each other's files, and `visible` false hides the zone. Asks
for approval.

### `list_course_news`

Lists the news items of a course, each with its id, whether pupils see it,
and its message as text with its formatting, in the form
[`post_course_news`](#post_course_news) takes. The message of an item pupils
do not see is not shown: Smartschool's news page leaves it out.

### `post_course_news`

Posts a news item with a title and a message in a course; pupils see it at
once unless `visible` is false, and get a notification with `notify`. The
message is written as the info of a lesfiche: plain text or simple Markdown
with bold, italic, underline, colours, lists and links (see
[Formatting in the info](lesfiches.md#formatting-in-the-info)). Asks for
approval.

## How it works

The tools use the library's `CourseService`; its
`doc/courses.md` has the requests and what Smartschool answers. Each tool
first reads the course menu and finds the course by its id or name
(`findCourse` in `lib/src/courses/courses.dart`): a course the menu does not
have, or a name several courses have, is refused with the courses there
are, before anything is sent. The course menu is not the course list of the
Lesfiches module: a course made in the course management is in the menu,
but not always in that list.

The writes are sent once and never again after logging in; the library
confirms each by the new item in the list it reads after the save. When it
cannot (`SmartschoolCourseWriteUnconfirmedError`), the tool says the item
may or may not have been made, and to check the list with the matching
`list_` tool before trying again. A refused file name, a missing file, or a
date that cannot be read is refused before anything is sent.

Dates are written `2026-12-01` or `2026-12-01 08:30`, in local time. A day
without a time is from 00:00 for a start, and until 23:59 for an end.

### Helpers and tests

- `lib/src/courses/courses.dart`: `withCourses` and `withCourseWrite` run the
  library's calls and turn its errors into tool errors; `findCourse`,
  `courseDateArgument` and the format functions.
- `test/course_tools_test.dart`: every tool over MCP against the fake
  Smartschool's courses (`test/support/fake_courses.dart`).
