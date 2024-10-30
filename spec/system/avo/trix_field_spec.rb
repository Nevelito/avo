require "rails_helper"

RSpec.describe "TrixField", type: :system do
  describe "without value" do
    let!(:post) { create :post, body: "" }

    context "show" do
      it "displays the posts empty body (dash)" do
        visit "/admin/resources/posts/#{post.id}"

        expect(find_field_element("body")).to have_text empty_dash
      end
    end

    context "edit" do
      it "has the posts body label and empty trix editor and placeholder" do
        visit "/admin/resources/posts/#{post.id}/edit"

        body_element = find_field_element("body")

        expect(body_element).to have_text "BODY"

        expect(find("#trix_post_body", visible: false)[:placeholder]).to have_text("Enter text")
        expect(find("#trix_post_body", visible: false)).to have_text("")
      end

      it "change the posts body text" do
        visit "/admin/resources/posts/#{post.id}/edit"

        fill_in_trix_editor "trix_post_body", with: "Works for us!!!"

        save

        expect(find_field_value_element("body")).to have_text "Works for us!!!"
      end
    end

    context "show" do
      it "displays the posts empty body (dash)" do
        visit "/admin/resources/posts/#{post.id}"

        expect(find_field_element("body")).to have_text empty_dash
      end
    end
  end

  describe "with regular value" do
    let!(:body) { "<div>Example trix text.</div>" }
    let!(:post) { create :post, body: body }

    context "show" do
      it "displays the posts body" do
        visit "/admin/resources/posts/#{post.id}"

        expect(page).not_to have_link("More content", href: "javascript:void(0);")
        expect(find_field_value_element("body")).to have_text ActionView::Base.full_sanitizer.sanitize(body)
      end

      context "when body has more then 1 line" do
        let!(:body) do
          <<~HTML
        <div>test1</div>
        <div>test2</div>
        <div>test3</div>
          HTML
        end

        it "displays correct button" do
          visit "/admin/resources/posts/#{post.id}"

          expect(page).to have_link("More content", href: "javascript:void(0);")
        end

        it "displays correct button after extended content" do
          visit "/admin/resources/posts/#{post.id}"

          click_on "More content"

          expect(page).to have_link("Less content", href: "javascript:void(0);")
        end
      end
    end

    context "edit" do
      it "has the posts body label" do
        visit "/admin/resources/posts/#{post.id}/edit"

        body_element = find_field_element("body")

        expect(body_element).to have_text "BODY"
      end

      it "has filled simple text in trix editor" do
        visit "/admin/resources/posts/#{post.id}/edit"

        expect(find("#trix_post_body", visible: false).value).to eq(body)
      end

      it "change the posts body trix to another simple text value" do
        visit "/admin/resources/posts/#{post.id}/edit"

        fill_in_trix_editor "trix_post_body", with: "New example!"

        save

        expect(find_field_value_element("body")).to have_text "New example!"
      end
    end
  end
end

def fill_in_trix_editor(id, with:)
  find("trix-editor[input='#{id}']").click.set(with)
end
