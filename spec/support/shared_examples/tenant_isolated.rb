# Proves that another organization's records can't be read or changed. Needs `user` (the signed-in HR user).
#
#   it_behaves_like "tenant isolated" do
#     let(:foreign_requests) do
#       [ [ :get, edit_thing_path(foreign) ], [ :patch, thing_path(foreign), { thing: { name: "x" } } ] ]
#     end
#   end
RSpec.shared_examples "tenant isolated" do
  it "returns 404 for another organization's records" do
    foreign_requests.each do |method, path, params|
      # A 404 raised as RecordNotFound doesn't write the session cookie, so Devise's test sign-in has to be
      # repeated for each request. (A real browser already holds a session cookie.)
      sign_in user
      public_send(method, path, params: params || {})
      expect(response).to have_http_status(:not_found), "expected #{method.upcase} #{path} to be 404, got #{response.status}"
    end
  end
end
