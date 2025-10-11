import lustre/attribute as a
import lustre/element/html as h

pub fn footer() {
  h.footer([a.class("mt-16 lg:mt-auto")], [
    h.section([a.class("flex justify-end"), a.id("publishing-docs")], [hint()]),
    h.section(
      [
        a.class("w-full"),
        a.class("border-t"),
        a.class("border-gray-200"),
        a.class("dark:border-gray-700"),
        a.class("flex"),
        a.class("flex-col"),
        a.class("lg:flex-row"),
        a.class("gap-4"),
        a.class("lg:gap-0"),
        a.class("justify-between"),
        a.class("text-sm"),
        a.class("px-4"),
        a.class("py-4"),
        a.id("footer"),
      ],
      [
        h.div([], [
          h.span([a.class("text-gray-600 dark:text-gray-200")], [
            h.text("Is something wrong? Let us know by "),
          ]),
          h.span([a.class("text-blue-600 dark:text-blue-600 font-medium")], [
            h.text("Opening an Issue"),
          ]),
          h.span([a.class("text-gray-600 dark:text-gray-200")], [h.text(" or ")]),
          h.span([a.class("text-blue-600 dark:text-blue-600 font-medium")], [
            h.text("Emailing Support"),
          ]),
        ]),
        h.div([a.class("text-gray-600 dark:text-gray-200")], [
          h.span([], [h.text("Search powered by Typesense")]),
        ]),
      ],
    ),
  ])
}

pub fn hint() {
  h.div([a.class("relative w-64 h-72")], [
    h.div(
      [
        a.class("absolute"),
        a.class("inset-0"),
        a.class("bg-gray-50"),
        a.class("dark:bg-gray-800"),
        a.class("rounded-tl-xl"),
        a.class("rounded-tr-xl"),
        a.class("z-10"),
      ],
      [
        h.div(
          [
            a.class("w-14"),
            a.class("h-14"),
            a.class("bg-gray-100"),
            a.class("dark:bg-gray-100"),
            a.class("rounded-full"),
            a.class("flex"),
            a.class("items-center"),
            a.class("justify-center"),
            a.class("m-3"),
          ],
          [
            h.i(
              [
                a.class("ri-contacts-book-upload-line"),
                a.class("text-gray-600"),
                a.class("dark:text-gray-600"),
                a.class("text-xl"),
              ],
              [],
            ),
          ],
        ),
        h.div([a.class("px-4 text-sm mt-4")], [
          h.h6([a.class("text-gray-700 dark:text-gray-100 font-semibold")], [
            h.text("Publishing Documentation"),
          ]),
          h.p([a.class("leading-tight mt-2")], [
            h.span([a.class("text-gray-500 dark:text-gray-200")], [
              h.text(
                "Documentation is automatically published when you publish
                your package, you can find more information ",
              ),
            ]),
            h.span([a.class("text-purple-700 font-medium")], [h.text("here")]),
            h.span([a.class("text-gray-500 dark:text-gray-200")], [h.text(".")]),
          ]),
          h.p([a.class("leading-tight mt-4")], [
            h.span([a.class("text-gray-500 dark:text-gray-200")], [
              h.text("Learn how to write documentation "),
            ]),
            h.span([a.class("text-purple-700 font-medium")], [h.text("here")]),
            h.span([a.class("text-gray-500 dark:text-gray-200")], [h.text(".")]),
          ]),
        ]),
      ],
    ),
    h.div(
      [
        a.class("absolute"),
        a.class("inset-0"),
        a.class("bg-gray-100"),
        a.class("dark:bg-gray-700"),
        a.class("rotate-6"),
        a.class("left-4"),
        a.class("rounded-tl-xl"),
        a.class("rounded-tr-xl"),
        a.class("z-0"),
      ],
      [],
    ),
  ])
}
